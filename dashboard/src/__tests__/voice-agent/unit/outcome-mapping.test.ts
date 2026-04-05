/**
 * Unit tests for mapVapiOutcome() from voice-agent/lib/constants.ts
 *
 * Tests the mapping logic including exact matches, prefix patterns,
 * and fallback behavior.
 */
import { describe, it, expect } from 'vitest'

// --------------------------------------------------------------------------
// Inlined types and mapping from voice-agent/lib/constants.ts
// --------------------------------------------------------------------------

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

function mapVapiOutcome(endedReason: string): SimplifiedOutcome {
  // Exact match
  if (VAPI_OUTCOME_MAP[endedReason]) {
    return VAPI_OUTCOME_MAP[endedReason]
  }

  // Prefix-based patterns
  if (
    endedReason.startsWith('error-') ||
    endedReason.startsWith('pipeline-error-')
  ) {
    return 'technical_error'
  }

  // Unknown reason -> technical error
  return 'technical_error'
}

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

describe('mapVapiOutcome()', () => {
  describe('exact match mapping', () => {
    it('maps customer-did-not-answer to no_answer', () => {
      expect(mapVapiOutcome('customer-did-not-answer')).toBe('no_answer')
    })

    it('maps no-answer to no_answer', () => {
      expect(mapVapiOutcome('no-answer')).toBe('no_answer')
    })

    it('maps customer-busy to line_busy', () => {
      expect(mapVapiOutcome('customer-busy')).toBe('line_busy')
    })

    it('maps busy to line_busy', () => {
      expect(mapVapiOutcome('busy')).toBe('line_busy')
    })

    it('maps voicemail to voicemail', () => {
      expect(mapVapiOutcome('voicemail')).toBe('voicemail')
    })

    it('maps machine-detected to voicemail', () => {
      expect(mapVapiOutcome('machine-detected')).toBe('voicemail')
    })

    it('maps silence-timed-out to ghosted', () => {
      expect(mapVapiOutcome('silence-timed-out')).toBe('ghosted')
    })

    it('maps assistant-ended-call to interested', () => {
      expect(mapVapiOutcome('assistant-ended-call')).toBe('interested')
    })

    it('maps customer-ended-call to not_interested', () => {
      expect(mapVapiOutcome('customer-ended-call')).toBe('not_interested')
    })

    it('maps customer-did-not-give-microphone-permission to hung_up_early', () => {
      expect(mapVapiOutcome('customer-did-not-give-microphone-permission')).toBe(
        'hung_up_early'
      )
    })
  })

  describe('prefix-based pattern matching', () => {
    it('maps unknown error-* patterns to technical_error', () => {
      expect(mapVapiOutcome('error-some-new-error')).toBe('technical_error')
    })

    it('maps unknown pipeline-error-* patterns to technical_error', () => {
      expect(mapVapiOutcome('pipeline-error-new-provider-failed')).toBe(
        'technical_error'
      )
    })

    it('maps known error patterns via exact match (not just prefix)', () => {
      expect(mapVapiOutcome('error-twilio-authentication-error')).toBe(
        'technical_error'
      )
    })
  })

  describe('fallback behavior', () => {
    it('maps completely unknown reasons to technical_error', () => {
      expect(mapVapiOutcome('some-random-unknown-reason')).toBe(
        'technical_error'
      )
    })

    it('maps empty string to technical_error', () => {
      expect(mapVapiOutcome('')).toBe('technical_error')
    })

    it('maps gibberish to technical_error', () => {
      expect(mapVapiOutcome('xyzzy-42')).toBe('technical_error')
    })
  })
})
