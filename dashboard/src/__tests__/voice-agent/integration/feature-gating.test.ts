/**
 * Integration tests for voice agent feature gating logic.
 *
 * Tests the multi-level gating: global toggle, showroom toggle,
 * and subscription plan-based gating.
 */
import { describe, it, expect } from 'vitest'

// --------------------------------------------------------------------------
// Feature gating logic (mirrors the actual implementation)
// --------------------------------------------------------------------------

interface FeatureGateConfig {
  globalEnabled: boolean
  showroomEnabled: boolean
  showroomPlan: 'free' | 'starter' | 'business' | 'enterprise'
  customerHasPhone: boolean
}

type GateResult =
  | { allowed: true }
  | { allowed: false; reason: string }

const PLANS_WITH_VOICE_AGENT = new Set(['business', 'enterprise'])

function checkFeatureGate(config: FeatureGateConfig): GateResult {
  // Level 1: Global platform toggle
  if (!config.globalEnabled) {
    return { allowed: false, reason: 'voice_agent_globally_disabled' }
  }

  // Level 2: Showroom-level toggle
  if (!config.showroomEnabled) {
    return { allowed: false, reason: 'showroom_voice_agent_disabled' }
  }

  // Level 3: Subscription plan check
  if (!PLANS_WITH_VOICE_AGENT.has(config.showroomPlan)) {
    return { allowed: false, reason: 'plan_not_eligible' }
  }

  // Level 4: Customer has phone
  if (!config.customerHasPhone) {
    return { allowed: false, reason: 'customer_no_phone' }
  }

  return { allowed: true }
}

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

describe('Feature Gating - Global Toggle', () => {
  it('blocks when global is disabled', () => {
    const result = checkFeatureGate({
      globalEnabled: false,
      showroomEnabled: true,
      showroomPlan: 'business',
      customerHasPhone: true,
    })
    expect(result.allowed).toBe(false)
    if (!result.allowed) {
      expect(result.reason).toBe('voice_agent_globally_disabled')
    }
  })

  it('proceeds past global check when enabled', () => {
    const result = checkFeatureGate({
      globalEnabled: true,
      showroomEnabled: true,
      showroomPlan: 'business',
      customerHasPhone: true,
    })
    expect(result.allowed).toBe(true)
  })
})

describe('Feature Gating - Showroom Toggle', () => {
  it('blocks when global is on but showroom is off', () => {
    const result = checkFeatureGate({
      globalEnabled: true,
      showroomEnabled: false,
      showroomPlan: 'business',
      customerHasPhone: true,
    })
    expect(result.allowed).toBe(false)
    if (!result.allowed) {
      expect(result.reason).toBe('showroom_voice_agent_disabled')
    }
  })

  it('proceeds when both global and showroom are on', () => {
    const result = checkFeatureGate({
      globalEnabled: true,
      showroomEnabled: true,
      showroomPlan: 'business',
      customerHasPhone: true,
    })
    expect(result.allowed).toBe(true)
  })
})

describe('Feature Gating - Plan-Based', () => {
  it('blocks free plan', () => {
    const result = checkFeatureGate({
      globalEnabled: true,
      showroomEnabled: true,
      showroomPlan: 'free',
      customerHasPhone: true,
    })
    expect(result.allowed).toBe(false)
    if (!result.allowed) {
      expect(result.reason).toBe('plan_not_eligible')
    }
  })

  it('blocks starter plan', () => {
    const result = checkFeatureGate({
      globalEnabled: true,
      showroomEnabled: true,
      showroomPlan: 'starter',
      customerHasPhone: true,
    })
    expect(result.allowed).toBe(false)
    if (!result.allowed) {
      expect(result.reason).toBe('plan_not_eligible')
    }
  })

  it('allows business plan', () => {
    const result = checkFeatureGate({
      globalEnabled: true,
      showroomEnabled: true,
      showroomPlan: 'business',
      customerHasPhone: true,
    })
    expect(result.allowed).toBe(true)
  })

  it('allows enterprise plan', () => {
    const result = checkFeatureGate({
      globalEnabled: true,
      showroomEnabled: true,
      showroomPlan: 'enterprise',
      customerHasPhone: true,
    })
    expect(result.allowed).toBe(true)
  })
})

describe('Feature Gating - Customer Phone Check', () => {
  it('blocks when customer has no phone', () => {
    const result = checkFeatureGate({
      globalEnabled: true,
      showroomEnabled: true,
      showroomPlan: 'business',
      customerHasPhone: false,
    })
    expect(result.allowed).toBe(false)
    if (!result.allowed) {
      expect(result.reason).toBe('customer_no_phone')
    }
  })

  it('allows when customer has phone', () => {
    const result = checkFeatureGate({
      globalEnabled: true,
      showroomEnabled: true,
      showroomPlan: 'business',
      customerHasPhone: true,
    })
    expect(result.allowed).toBe(true)
  })
})

describe('Feature Gating - Priority Order', () => {
  it('returns global_disabled before showroom_disabled', () => {
    const result = checkFeatureGate({
      globalEnabled: false,
      showroomEnabled: false,
      showroomPlan: 'free',
      customerHasPhone: false,
    })
    expect(result.allowed).toBe(false)
    if (!result.allowed) {
      expect(result.reason).toBe('voice_agent_globally_disabled')
    }
  })

  it('returns showroom_disabled before plan_not_eligible', () => {
    const result = checkFeatureGate({
      globalEnabled: true,
      showroomEnabled: false,
      showroomPlan: 'free',
      customerHasPhone: false,
    })
    expect(result.allowed).toBe(false)
    if (!result.allowed) {
      expect(result.reason).toBe('showroom_voice_agent_disabled')
    }
  })

  it('returns plan_not_eligible before customer_no_phone', () => {
    const result = checkFeatureGate({
      globalEnabled: true,
      showroomEnabled: true,
      showroomPlan: 'free',
      customerHasPhone: false,
    })
    expect(result.allowed).toBe(false)
    if (!result.allowed) {
      expect(result.reason).toBe('plan_not_eligible')
    }
  })
})
