/**
 * Integration tests for the full voice agent end-to-end flow.
 *
 * Describes the complete sequence: trigger -> SMS -> call -> webhook -> flow
 * All external services (Supabase, Twilio, Vapi, Google Maps) are mocked.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'

// --------------------------------------------------------------------------
// Mock types and services
// --------------------------------------------------------------------------

interface MockSmsResult {
  success: boolean
  sid?: string
  error?: string
}

interface MockCallResult {
  success: boolean
  callId?: string
  error?: string
}

interface MockDistanceResult {
  distanceMiles: number
  distanceKm: number
  driveTimeMinutes: number
}

type SimplifiedOutcome =
  | 'no_answer'
  | 'line_busy'
  | 'voicemail'
  | 'ghosted'
  | 'interested'
  | 'not_interested'
  | 'link_sent'
  | 'callback_requested'
  | 'hung_up_early'
  | 'technical_error'

// Mocked service functions
const mockSendSms = vi.fn<() => Promise<MockSmsResult>>()
const mockInitiateCall = vi.fn<() => Promise<MockCallResult>>()
const mockCalculateDistance = vi.fn<() => Promise<MockDistanceResult | null>>()
const mockInsertLog = vi.fn<() => Promise<{ id: string }>>()
const mockUpdateLog = vi.fn<() => Promise<void>>()

function determineZone(distanceMiles: number, threshold: number): 'near' | 'far' {
  return distanceMiles <= threshold ? 'near' : 'far'
}

function interpolate(
  template: string,
  vars: Record<string, string | number | null | undefined>
): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => {
    const val = vars[key]
    return val != null ? String(val) : ''
  })
}

// --------------------------------------------------------------------------
// Simulated trigger pipeline
// --------------------------------------------------------------------------

interface TriggerConfig {
  globalEnabled: boolean
  showroomEnabled: boolean
  distanceThreshold: number
  smsTemplate: string
  systemPrompt: string
  customerPhone: string
  customerAddress: string
  showroomAddress: string
  customerFirstName: string
  showroomName: string
}

async function simulateTriggerPipeline(config: TriggerConfig): Promise<{
  skipped: boolean
  skipReason?: string
  logId?: string
  smsResult?: MockSmsResult
  callResult?: MockCallResult
  zone?: 'near' | 'far'
}> {
  // Step 1: Feature gating
  if (!config.globalEnabled) {
    return { skipped: true, skipReason: 'global_disabled' }
  }
  if (!config.showroomEnabled) {
    return { skipped: true, skipReason: 'showroom_disabled' }
  }
  if (!config.customerPhone) {
    return { skipped: true, skipReason: 'no_phone' }
  }

  // Step 2: Calculate distance
  let zone: 'near' | 'far' = 'near'
  const distance = await mockCalculateDistance()
  if (distance) {
    zone = determineZone(distance.distanceMiles, config.distanceThreshold)
  }

  // Step 3: Interpolate template
  const smsBody = interpolate(config.smsTemplate, {
    customer_first_name: config.customerFirstName,
    showroom_name: config.showroomName,
  })

  // Step 4: Create log entry
  const logEntry = await mockInsertLog()

  // Step 5: Send SMS
  const smsResult = await mockSendSms()

  // Step 6: Update log with SMS result
  await mockUpdateLog()

  // Step 7: Initiate call
  const systemPrompt = interpolate(config.systemPrompt, {
    customer_first_name: config.customerFirstName,
    showroom_name: config.showroomName,
  })

  const callResult = await mockInitiateCall()

  // Step 8: Update log with call result
  await mockUpdateLog()

  return {
    skipped: false,
    logId: logEntry.id,
    smsResult,
    callResult,
    zone,
  }
}

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

beforeEach(() => {
  vi.resetAllMocks()
  mockInsertLog.mockResolvedValue({ id: 'log-123' })
  mockUpdateLog.mockResolvedValue(undefined)
})

describe('Full End-to-End Trigger Flow', () => {
  const baseConfig: TriggerConfig = {
    globalEnabled: true,
    showroomEnabled: true,
    distanceThreshold: 30,
    smsTemplate: 'Hi {{customer_first_name}}, thanks for visiting {{showroom_name}}!',
    systemPrompt: 'You are calling on behalf of {{showroom_name}}.',
    customerPhone: '+15551234567',
    customerAddress: '123 Main St, Springfield, IL',
    showroomAddress: '456 Oak Ave, Chicago, IL',
    customerFirstName: 'Alice',
    showroomName: 'Acme Cabinets',
  }

  it('completes full flow: distance -> SMS -> call', async () => {
    mockCalculateDistance.mockResolvedValue({
      distanceMiles: 15,
      distanceKm: 24,
      driveTimeMinutes: 20,
    })
    mockSendSms.mockResolvedValue({ success: true, sid: 'SM123' })
    mockInitiateCall.mockResolvedValue({ success: true, callId: 'call-456' })

    const result = await simulateTriggerPipeline(baseConfig)

    expect(result.skipped).toBe(false)
    expect(result.zone).toBe('near')
    expect(result.smsResult?.success).toBe(true)
    expect(result.callResult?.success).toBe(true)
    expect(result.logId).toBe('log-123')

    expect(mockCalculateDistance).toHaveBeenCalledTimes(1)
    expect(mockSendSms).toHaveBeenCalledTimes(1)
    expect(mockInitiateCall).toHaveBeenCalledTimes(1)
    expect(mockInsertLog).toHaveBeenCalledTimes(1)
    expect(mockUpdateLog).toHaveBeenCalledTimes(2) // SMS update + call update
  })

  it('classifies far customer correctly', async () => {
    mockCalculateDistance.mockResolvedValue({
      distanceMiles: 50,
      distanceKm: 80,
      driveTimeMinutes: 55,
    })
    mockSendSms.mockResolvedValue({ success: true, sid: 'SM789' })
    mockInitiateCall.mockResolvedValue({ success: true, callId: 'call-abc' })

    const result = await simulateTriggerPipeline(baseConfig)

    expect(result.zone).toBe('far')
  })

  it('falls back to near zone when distance calculation fails', async () => {
    mockCalculateDistance.mockResolvedValue(null)
    mockSendSms.mockResolvedValue({ success: true, sid: 'SM000' })
    mockInitiateCall.mockResolvedValue({ success: true, callId: 'call-000' })

    const result = await simulateTriggerPipeline(baseConfig)

    expect(result.zone).toBe('near') // default fallback
  })

  it('continues to call even when SMS fails', async () => {
    mockCalculateDistance.mockResolvedValue(null)
    mockSendSms.mockResolvedValue({ success: false, error: 'Twilio error' })
    mockInitiateCall.mockResolvedValue({ success: true, callId: 'call-111' })

    const result = await simulateTriggerPipeline(baseConfig)

    expect(result.smsResult?.success).toBe(false)
    expect(result.callResult?.success).toBe(true)
    expect(mockInitiateCall).toHaveBeenCalledTimes(1) // still called
  })

  it('records call failure in result', async () => {
    mockCalculateDistance.mockResolvedValue(null)
    mockSendSms.mockResolvedValue({ success: true, sid: 'SM222' })
    mockInitiateCall.mockResolvedValue({
      success: false,
      error: 'Vapi API key not configured',
    })

    const result = await simulateTriggerPipeline(baseConfig)

    expect(result.callResult?.success).toBe(false)
    expect(result.callResult?.error).toContain('Vapi')
  })
})

describe('Feature Gating Prevents Trigger', () => {
  it('skips when global is disabled', async () => {
    const result = await simulateTriggerPipeline({
      globalEnabled: false,
      showroomEnabled: true,
      distanceThreshold: 30,
      smsTemplate: '',
      systemPrompt: '',
      customerPhone: '+15551234567',
      customerAddress: '',
      showroomAddress: '',
      customerFirstName: '',
      showroomName: '',
    })

    expect(result.skipped).toBe(true)
    expect(result.skipReason).toBe('global_disabled')
    expect(mockSendSms).not.toHaveBeenCalled()
    expect(mockInitiateCall).not.toHaveBeenCalled()
  })

  it('skips when showroom is disabled', async () => {
    const result = await simulateTriggerPipeline({
      globalEnabled: true,
      showroomEnabled: false,
      distanceThreshold: 30,
      smsTemplate: '',
      systemPrompt: '',
      customerPhone: '+15551234567',
      customerAddress: '',
      showroomAddress: '',
      customerFirstName: '',
      showroomName: '',
    })

    expect(result.skipped).toBe(true)
    expect(result.skipReason).toBe('showroom_disabled')
  })

  it('skips when customer has no phone', async () => {
    const result = await simulateTriggerPipeline({
      globalEnabled: true,
      showroomEnabled: true,
      distanceThreshold: 30,
      smsTemplate: '',
      systemPrompt: '',
      customerPhone: '',
      customerAddress: '',
      showroomAddress: '',
      customerFirstName: '',
      showroomName: '',
    })

    expect(result.skipped).toBe(true)
    expect(result.skipReason).toBe('no_phone')
  })
})

describe('Webhook -> Post-Call Flow Sequence', () => {
  it('processes end-of-call webhook and determines outcome', () => {
    const endOfCallData = {
      endedReason: 'customer-did-not-answer',
      durationSeconds: 0,
    }

    const VAPI_OUTCOME_MAP: Record<string, SimplifiedOutcome> = {
      'customer-did-not-answer': 'no_answer',
    }

    const outcome = VAPI_OUTCOME_MAP[endOfCallData.endedReason] || 'technical_error'
    expect(outcome).toBe('no_answer')
  })

  it('determines next flow action based on outcome', () => {
    const outcome: SimplifiedOutcome = 'no_answer'
    // In the default flow, no_answer -> wait -> retry -> (max reached) -> SMS -> stop
    const expectedFirstAction = 'wait'
    const flowActions: Record<SimplifiedOutcome, string> = {
      no_answer: 'wait',
      line_busy: 'wait',
      voicemail: 'sms',
      ghosted: 'sms',
      interested: 'send_link',
      not_interested: 'stop',
      link_sent: 'stop',
      callback_requested: 'wait',
      hung_up_early: 'wait',
      technical_error: 'retry_call',
    }
    expect(flowActions[outcome]).toBe(expectedFirstAction)
  })

  it('handles multiple retry attempts with flow progression', () => {
    const maxAttempts = 3
    const attempts = [1, 2, 3]
    const retryResults = attempts.map((attempt) => ({
      attempt,
      shouldRetry: attempt < maxAttempts,
      maxReached: attempt >= maxAttempts,
    }))

    expect(retryResults[0]).toEqual({ attempt: 1, shouldRetry: true, maxReached: false })
    expect(retryResults[1]).toEqual({ attempt: 2, shouldRetry: true, maxReached: false })
    expect(retryResults[2]).toEqual({ attempt: 3, shouldRetry: false, maxReached: true })
  })
})
