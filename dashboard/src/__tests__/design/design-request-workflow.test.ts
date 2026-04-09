/**
 * Unit Tests: Design Request Workflow - Status State Machine
 *
 * Tests the design request status transition logic and business rules.
 * These are pure logic tests that don't require a database connection.
 */
import { describe, it, expect, beforeEach, vi } from 'vitest'

// ---- Status Transition State Machine ----

type DesignRequestStatus =
  | 'pending'
  | 'accepted'
  | 'in_progress'
  | 'delivered'
  | 'approved'
  | 'revision_requested'
  | 'completed'
  | 'canceled'

/**
 * Valid status transitions for design requests.
 * This mirrors the business logic enforced by the database constraint
 * and the application-level controls.
 */
const VALID_TRANSITIONS: Record<DesignRequestStatus, DesignRequestStatus[]> = {
  pending: ['accepted', 'canceled'],
  accepted: ['in_progress', 'canceled'],
  in_progress: ['delivered', 'canceled'],
  delivered: ['approved', 'revision_requested', 'canceled'],
  approved: ['completed', 'canceled'],
  revision_requested: ['in_progress', 'canceled'],
  completed: [],
  canceled: [],
}

/**
 * Checks whether a status transition is valid.
 */
function isValidTransition(
  from: DesignRequestStatus,
  to: DesignRequestStatus
): boolean {
  return VALID_TRANSITIONS[from]?.includes(to) ?? false
}

/**
 * Represents a design request record.
 */
interface DesignRequest {
  id: string
  project_id: string
  showroom_id: string
  designer_id: string | null
  status: DesignRequestStatus
  priority: string
  notes: string | null
  accepted_at: string | null
  delivered_at: string | null
  approved_at: string | null
  completed_at: string | null
  created_at: string
}

/**
 * Applies a status transition to a design request, returning the updated request.
 * Throws if the transition is invalid.
 */
function applyTransition(
  request: DesignRequest,
  newStatus: DesignRequestStatus,
  extraFields: Partial<DesignRequest> = {}
): DesignRequest {
  if (!isValidTransition(request.status, newStatus)) {
    throw new Error(
      `Invalid status transition: ${request.status} -> ${newStatus}`
    )
  }
  return { ...request, status: newStatus, ...extraFields }
}

/**
 * Simulates accepting a design request with optimistic locking.
 * Returns { success, request } -- success is false if the request
 * was already accepted (race condition).
 */
function acceptRequest(
  request: DesignRequest,
  designerId: string
): { success: boolean; request: DesignRequest } {
  if (request.status !== 'pending') {
    return { success: false, request }
  }
  const updated = applyTransition(request, 'accepted', {
    designer_id: designerId,
    accepted_at: new Date().toISOString(),
  })
  return { success: true, request: updated }
}

// ---- Helper to create a test request ----

function createTestRequest(
  overrides: Partial<DesignRequest> = {}
): DesignRequest {
  return {
    id: 'dr-001',
    project_id: 'proj-001',
    showroom_id: 'sr-001',
    designer_id: null,
    status: 'pending',
    priority: 'normal',
    notes: null,
    accepted_at: null,
    delivered_at: null,
    approved_at: null,
    completed_at: null,
    created_at: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

// ---- Tests ----

describe('Design Request Workflow', () => {
  describe('Status Transitions - Valid', () => {
    it('should allow pending -> accepted', () => {
      expect(isValidTransition('pending', 'accepted')).toBe(true)
    })

    it('should allow accepted -> in_progress', () => {
      expect(isValidTransition('accepted', 'in_progress')).toBe(true)
    })

    it('should allow in_progress -> delivered', () => {
      expect(isValidTransition('in_progress', 'delivered')).toBe(true)
    })

    it('should allow delivered -> approved', () => {
      expect(isValidTransition('delivered', 'approved')).toBe(true)
    })

    it('should allow delivered -> revision_requested', () => {
      expect(isValidTransition('delivered', 'revision_requested')).toBe(true)
    })

    it('should allow revision_requested -> in_progress', () => {
      expect(isValidTransition('revision_requested', 'in_progress')).toBe(true)
    })

    it('should allow approved -> completed', () => {
      expect(isValidTransition('approved', 'completed')).toBe(true)
    })

    it('should allow any active status -> canceled', () => {
      const activeStatuses: DesignRequestStatus[] = [
        'pending',
        'accepted',
        'in_progress',
        'delivered',
        'approved',
        'revision_requested',
      ]
      for (const status of activeStatuses) {
        expect(isValidTransition(status, 'canceled')).toBe(true)
      }
    })
  })

  describe('Status Transitions - Invalid', () => {
    it('should not allow pending -> delivered', () => {
      expect(isValidTransition('pending', 'delivered')).toBe(false)
    })

    it('should not allow pending -> in_progress', () => {
      expect(isValidTransition('pending', 'in_progress')).toBe(false)
    })

    it('should not allow pending -> approved', () => {
      expect(isValidTransition('pending', 'approved')).toBe(false)
    })

    it('should not allow pending -> completed', () => {
      expect(isValidTransition('pending', 'completed')).toBe(false)
    })

    it('should not allow completed -> any status', () => {
      const allStatuses: DesignRequestStatus[] = [
        'pending',
        'accepted',
        'in_progress',
        'delivered',
        'approved',
        'revision_requested',
        'completed',
        'canceled',
      ]
      for (const status of allStatuses) {
        expect(isValidTransition('completed', status)).toBe(false)
      }
    })

    it('should not allow canceled -> any status', () => {
      const allStatuses: DesignRequestStatus[] = [
        'pending',
        'accepted',
        'in_progress',
        'delivered',
        'approved',
        'revision_requested',
        'completed',
        'canceled',
      ]
      for (const status of allStatuses) {
        expect(isValidTransition('canceled', status)).toBe(false)
      }
    })

    it('should not allow in_progress -> accepted', () => {
      expect(isValidTransition('in_progress', 'accepted')).toBe(false)
    })

    it('should not allow delivered -> in_progress (must go through revision_requested)', () => {
      expect(isValidTransition('delivered', 'in_progress')).toBe(false)
    })

    it('should not allow approved -> in_progress', () => {
      expect(isValidTransition('approved', 'in_progress')).toBe(false)
    })

    it('should not allow accepted -> delivered (must go through in_progress)', () => {
      expect(isValidTransition('accepted', 'delivered')).toBe(false)
    })
  })

  describe('applyTransition', () => {
    it('should update the status for a valid transition', () => {
      const request = createTestRequest({ status: 'pending' })
      const updated = applyTransition(request, 'accepted', {
        designer_id: 'designer-1',
        accepted_at: '2026-01-02T00:00:00.000Z',
      })
      expect(updated.status).toBe('accepted')
      expect(updated.designer_id).toBe('designer-1')
      expect(updated.accepted_at).toBe('2026-01-02T00:00:00.000Z')
    })

    it('should throw for an invalid transition', () => {
      const request = createTestRequest({ status: 'pending' })
      expect(() => applyTransition(request, 'delivered')).toThrow(
        'Invalid status transition: pending -> delivered'
      )
    })

    it('should throw when trying to move completed to in_progress', () => {
      const request = createTestRequest({ status: 'completed' })
      expect(() => applyTransition(request, 'in_progress')).toThrow(
        'Invalid status transition: completed -> in_progress'
      )
    })

    it('should preserve other fields during transition', () => {
      const request = createTestRequest({
        status: 'in_progress',
        designer_id: 'designer-1',
        notes: 'Modern style kitchen',
        priority: 'high',
      })
      const updated = applyTransition(request, 'delivered', {
        delivered_at: '2026-01-05T00:00:00.000Z',
      })
      expect(updated.notes).toBe('Modern style kitchen')
      expect(updated.priority).toBe('high')
      expect(updated.designer_id).toBe('designer-1')
      expect(updated.delivered_at).toBe('2026-01-05T00:00:00.000Z')
    })
  })

  describe('Complete Workflow - Happy Path', () => {
    it('should progress through the full lifecycle', () => {
      let request = createTestRequest()

      // Step 1: Accept
      request = applyTransition(request, 'accepted', {
        designer_id: 'designer-1',
        accepted_at: '2026-01-02T00:00:00.000Z',
      })
      expect(request.status).toBe('accepted')
      expect(request.designer_id).toBe('designer-1')

      // Step 2: Start working
      request = applyTransition(request, 'in_progress')
      expect(request.status).toBe('in_progress')

      // Step 3: Deliver
      request = applyTransition(request, 'delivered', {
        delivered_at: '2026-01-05T00:00:00.000Z',
      })
      expect(request.status).toBe('delivered')
      expect(request.delivered_at).toBe('2026-01-05T00:00:00.000Z')

      // Step 4: Approve
      request = applyTransition(request, 'approved', {
        approved_at: '2026-01-06T00:00:00.000Z',
      })
      expect(request.status).toBe('approved')

      // Step 5: Complete
      request = applyTransition(request, 'completed', {
        completed_at: '2026-01-07T00:00:00.000Z',
      })
      expect(request.status).toBe('completed')
    })

    it('should handle the revision loop', () => {
      let request = createTestRequest({ status: 'delivered' })

      // Revision requested
      request = applyTransition(request, 'revision_requested')
      expect(request.status).toBe('revision_requested')

      // Resume work
      request = applyTransition(request, 'in_progress')
      expect(request.status).toBe('in_progress')

      // Re-deliver
      request = applyTransition(request, 'delivered', {
        delivered_at: '2026-01-10T00:00:00.000Z',
      })
      expect(request.status).toBe('delivered')

      // Now approve
      request = applyTransition(request, 'approved', {
        approved_at: '2026-01-11T00:00:00.000Z',
      })
      expect(request.status).toBe('approved')
    })
  })

  describe('Race Condition Prevention', () => {
    it('should only accept if status is still pending', () => {
      const request = createTestRequest({ status: 'pending' })

      // First designer accepts
      const result1 = acceptRequest(request, 'designer-A')
      expect(result1.success).toBe(true)
      expect(result1.request.designer_id).toBe('designer-A')
      expect(result1.request.status).toBe('accepted')
      expect(result1.request.accepted_at).not.toBeNull()

      // Second designer tries to accept the already-accepted request
      const result2 = acceptRequest(result1.request, 'designer-B')
      expect(result2.success).toBe(false)
      // The request should remain unchanged
      expect(result2.request.designer_id).toBe('designer-A')
      expect(result2.request.status).toBe('accepted')
    })

    it('should reject acceptance of a canceled request', () => {
      const request = createTestRequest({ status: 'canceled' })
      const result = acceptRequest(request, 'designer-A')
      expect(result.success).toBe(false)
      expect(result.request.status).toBe('canceled')
    })

    it('should reject acceptance of an already in_progress request', () => {
      const request = createTestRequest({
        status: 'in_progress',
        designer_id: 'designer-A',
      })
      const result = acceptRequest(request, 'designer-B')
      expect(result.success).toBe(false)
      expect(result.request.designer_id).toBe('designer-A')
    })
  })

  describe('Cancellation', () => {
    it('should allow cancellation from pending', () => {
      const request = createTestRequest({ status: 'pending' })
      const updated = applyTransition(request, 'canceled')
      expect(updated.status).toBe('canceled')
    })

    it('should allow cancellation from accepted', () => {
      const request = createTestRequest({ status: 'accepted' })
      const updated = applyTransition(request, 'canceled')
      expect(updated.status).toBe('canceled')
    })

    it('should allow cancellation from in_progress', () => {
      const request = createTestRequest({ status: 'in_progress' })
      const updated = applyTransition(request, 'canceled')
      expect(updated.status).toBe('canceled')
    })

    it('should allow cancellation from delivered', () => {
      const request = createTestRequest({ status: 'delivered' })
      const updated = applyTransition(request, 'canceled')
      expect(updated.status).toBe('canceled')
    })

    it('should not allow cancellation from completed', () => {
      const request = createTestRequest({ status: 'completed' })
      expect(() => applyTransition(request, 'canceled')).toThrow(
        'Invalid status transition: completed -> canceled'
      )
    })

    it('should not allow cancellation from already canceled', () => {
      const request = createTestRequest({ status: 'canceled' })
      expect(() => applyTransition(request, 'canceled')).toThrow(
        'Invalid status transition: canceled -> canceled'
      )
    })
  })

  describe('Edge Cases', () => {
    it('should not allow self-transition (same status)', () => {
      const statuses: DesignRequestStatus[] = [
        'pending',
        'accepted',
        'in_progress',
        'delivered',
        'approved',
        'revision_requested',
        'completed',
        'canceled',
      ]
      for (const status of statuses) {
        expect(isValidTransition(status, status)).toBe(false)
      }
    })

    it('should not allow backward transitions in the main flow', () => {
      expect(isValidTransition('accepted', 'pending')).toBe(false)
      expect(isValidTransition('in_progress', 'accepted')).toBe(false)
      expect(isValidTransition('delivered', 'in_progress')).toBe(false)
      expect(isValidTransition('approved', 'delivered')).toBe(false)
      expect(isValidTransition('completed', 'approved')).toBe(false)
    })

    it('should handle multiple revision cycles', () => {
      let request = createTestRequest({ status: 'delivered' })

      // Cycle 1
      request = applyTransition(request, 'revision_requested')
      request = applyTransition(request, 'in_progress')
      request = applyTransition(request, 'delivered')

      // Cycle 2
      request = applyTransition(request, 'revision_requested')
      request = applyTransition(request, 'in_progress')
      request = applyTransition(request, 'delivered')

      // Cycle 3
      request = applyTransition(request, 'revision_requested')
      request = applyTransition(request, 'in_progress')
      request = applyTransition(request, 'delivered')

      // Finally approve
      request = applyTransition(request, 'approved')
      expect(request.status).toBe('approved')
    })
  })
})
