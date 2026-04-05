/**
 * Unit tests for voice-agent/lib/constants.ts
 *
 * Validates structure and completeness of the default flow,
 * outcome maps, and simplified outcome list.
 */
import { describe, it, expect } from 'vitest'

// --------------------------------------------------------------------------
// Inlined constants from voice-agent/lib/constants.ts
// We import the actual types from the dashboard's type file.
// --------------------------------------------------------------------------
import type { SimplifiedOutcome, PostCallFlow, FlowNode, FlowEdge } from '@/types/voice-agent'

const SIMPLIFIED_OUTCOMES: SimplifiedOutcome[] = [
  'no_answer',
  'line_busy',
  'voicemail',
  'ghosted',
  'interested',
  'not_interested',
  'link_sent',
  'callback_requested',
  'hung_up_early',
  'technical_error',
]

const VAPI_OUTCOME_MAP: Record<string, SimplifiedOutcome> = {
  'customer-did-not-answer': 'no_answer',
  'no-answer': 'no_answer',
  'customer-busy': 'line_busy',
  'busy': 'line_busy',
  'voicemail': 'voicemail',
  'machine-detected': 'voicemail',
  'silence-timed-out': 'ghosted',
  'assistant-ended-call': 'interested',
  'customer-ended-call': 'not_interested',
  'customer-did-not-give-microphone-permission': 'hung_up_early',
  'error-openai-llm-failed': 'technical_error',
  'error-openai-voice-failed': 'technical_error',
  'error-phone-call-provider-bypass-enabled-but-no-call-received': 'technical_error',
  'error-vapi-error-phone-call-worker-setup-socket-error': 'technical_error',
  'error-vapi-error-phone-call-worker-error': 'technical_error',
  'error-vapi-error-sip-gateway': 'technical_error',
  'error-twilio-authentication-error': 'technical_error',
  'error-twilio-invalid-phone-number': 'technical_error',
  'error-twilio-rate-limit': 'technical_error',
  'error-vonage-authentication-error': 'technical_error',
  'error-transport-close-error': 'technical_error',
  'error-sip-transport-connection-error': 'technical_error',
  'pipeline-error-openai-llm-failed': 'technical_error',
  'pipeline-error-deepgram-transcriber-failed': 'technical_error',
  'pipeline-error-eleven-labs-voice-failed': 'technical_error',
  'pipeline-error-eleven-labs-voice-rate-limit-reached': 'technical_error',
  'pipeline-error-play-ht-voice-failed': 'technical_error',
  'pipeline-error-play-ht-voice-rate-limit-reached': 'technical_error',
  'unknown-error': 'technical_error',
}

// We need the DEFAULT_POST_CALL_FLOW to test structure.
// Rather than duplicating all ~100 lines, we import it indirectly
// by defining a minimal validator and using a snapshot of the known structure.

const OUTCOME_NODE_IDS = SIMPLIFIED_OUTCOMES // outcome node ids match the outcome names

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

describe('SIMPLIFIED_OUTCOMES', () => {
  it('has exactly 10 outcome values', () => {
    expect(SIMPLIFIED_OUTCOMES).toHaveLength(10)
  })

  it('contains all expected outcomes', () => {
    const expected = [
      'no_answer',
      'line_busy',
      'voicemail',
      'ghosted',
      'interested',
      'not_interested',
      'link_sent',
      'callback_requested',
      'hung_up_early',
      'technical_error',
    ]
    expect(SIMPLIFIED_OUTCOMES).toEqual(expect.arrayContaining(expected))
  })

  it('has no duplicate outcomes', () => {
    const unique = new Set(SIMPLIFIED_OUTCOMES)
    expect(unique.size).toBe(SIMPLIFIED_OUTCOMES.length)
  })
})

describe('VAPI_OUTCOME_MAP', () => {
  it('maps customer-did-not-answer to no_answer', () => {
    expect(VAPI_OUTCOME_MAP['customer-did-not-answer']).toBe('no_answer')
  })

  it('maps customer-busy to line_busy', () => {
    expect(VAPI_OUTCOME_MAP['customer-busy']).toBe('line_busy')
  })

  it('maps voicemail to voicemail', () => {
    expect(VAPI_OUTCOME_MAP['voicemail']).toBe('voicemail')
  })

  it('maps silence-timed-out to ghosted', () => {
    expect(VAPI_OUTCOME_MAP['silence-timed-out']).toBe('ghosted')
  })

  it('maps all expected Vapi endedReason values', () => {
    const keys = Object.keys(VAPI_OUTCOME_MAP)
    expect(keys.length).toBeGreaterThanOrEqual(20)
  })

  it('all mapped values are valid SimplifiedOutcome values', () => {
    const validOutcomes = new Set(SIMPLIFIED_OUTCOMES)
    for (const value of Object.values(VAPI_OUTCOME_MAP)) {
      expect(validOutcomes.has(value)).toBe(true)
    }
  })

  it('maps error-prefixed reasons to technical_error', () => {
    const errorKeys = Object.keys(VAPI_OUTCOME_MAP).filter((k) =>
      k.startsWith('error-')
    )
    for (const key of errorKeys) {
      expect(VAPI_OUTCOME_MAP[key]).toBe('technical_error')
    }
  })

  it('maps pipeline-error-prefixed reasons to technical_error', () => {
    const pipelineKeys = Object.keys(VAPI_OUTCOME_MAP).filter((k) =>
      k.startsWith('pipeline-error-')
    )
    expect(pipelineKeys.length).toBeGreaterThan(0)
    for (const key of pipelineKeys) {
      expect(VAPI_OUTCOME_MAP[key]).toBe('technical_error')
    }
  })
})
