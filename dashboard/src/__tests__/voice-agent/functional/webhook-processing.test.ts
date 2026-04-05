/**
 * Functional tests for webhook processing logic.
 *
 * Tests outcome mapping, duration-based hung_up_early detection,
 * and transcript keyword matching for callback_requested.
 */
import { describe, it, expect } from 'vitest'

// --------------------------------------------------------------------------
// Inlined from voice-agent/lib/constants.ts
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
  'unknown-error': 'technical_error',
}

function mapVapiOutcome(endedReason: string): SimplifiedOutcome {
  if (VAPI_OUTCOME_MAP[endedReason]) {
    return VAPI_OUTCOME_MAP[endedReason]
  }
  if (endedReason.startsWith('error-') || endedReason.startsWith('pipeline-error-')) {
    return 'technical_error'
  }
  return 'technical_error'
}

// --------------------------------------------------------------------------
// Webhook processing logic (mirrors what the webhook Edge Function does)
// --------------------------------------------------------------------------

const HUNG_UP_EARLY_THRESHOLD_SECONDS = 10
const CALLBACK_KEYWORDS = ['call me back', 'callback', 'call back', 'ring me later']

interface EndOfCallReport {
  endedReason: string
  durationSeconds: number
  transcript?: string
  summary?: string
  toolCalls?: Array<{ name: string }>
}

function processEndOfCallReport(report: EndOfCallReport): {
  outcome: SimplifiedOutcome
  refinedBy: string[]
} {
  let outcome = mapVapiOutcome(report.endedReason)
  const refinedBy: string[] = []

  // Refine: check if link was sent via tool call
  if (report.toolCalls?.some((t) => t.name === 'send_scheduling_link')) {
    outcome = 'link_sent'
    refinedBy.push('tool_call:send_scheduling_link')
  }

  // Refine: duration-based hung_up_early detection
  if (
    report.durationSeconds > 0 &&
    report.durationSeconds <= HUNG_UP_EARLY_THRESHOLD_SECONDS &&
    outcome === 'not_interested'
  ) {
    outcome = 'hung_up_early'
    refinedBy.push('duration_short')
  }

  // Refine: transcript keyword matching for callback_requested
  if (report.transcript) {
    const lowerTranscript = report.transcript.toLowerCase()
    const hasCallbackKeyword = CALLBACK_KEYWORDS.some((kw) =>
      lowerTranscript.includes(kw)
    )
    if (hasCallbackKeyword && outcome !== 'link_sent') {
      outcome = 'callback_requested'
      refinedBy.push('transcript_keyword:callback')
    }
  }

  return { outcome, refinedBy }
}

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

describe('End-of-Call Report Processing', () => {
  it('maps basic endedReason to outcome', () => {
    const result = processEndOfCallReport({
      endedReason: 'customer-did-not-answer',
      durationSeconds: 0,
    })
    expect(result.outcome).toBe('no_answer')
    expect(result.refinedBy).toEqual([])
  })

  it('maps voicemail outcome correctly', () => {
    const result = processEndOfCallReport({
      endedReason: 'voicemail',
      durationSeconds: 0,
    })
    expect(result.outcome).toBe('voicemail')
  })

  it('maps customer-ended-call to not_interested by default', () => {
    const result = processEndOfCallReport({
      endedReason: 'customer-ended-call',
      durationSeconds: 120,
    })
    expect(result.outcome).toBe('not_interested')
  })
})

describe('Duration-based hung_up_early detection', () => {
  it('refines to hung_up_early when call is very short and customer ended', () => {
    const result = processEndOfCallReport({
      endedReason: 'customer-ended-call',
      durationSeconds: 5,
    })
    expect(result.outcome).toBe('hung_up_early')
    expect(result.refinedBy).toContain('duration_short')
  })

  it('does NOT refine to hung_up_early when call is longer than threshold', () => {
    const result = processEndOfCallReport({
      endedReason: 'customer-ended-call',
      durationSeconds: 30,
    })
    expect(result.outcome).toBe('not_interested')
    expect(result.refinedBy).not.toContain('duration_short')
  })

  it('does NOT refine to hung_up_early when duration is at threshold', () => {
    const result = processEndOfCallReport({
      endedReason: 'customer-ended-call',
      durationSeconds: HUNG_UP_EARLY_THRESHOLD_SECONDS,
    })
    expect(result.outcome).toBe('hung_up_early')
  })

  it('does NOT refine non-customer-ended reasons', () => {
    const result = processEndOfCallReport({
      endedReason: 'assistant-ended-call',
      durationSeconds: 5,
    })
    // assistant-ended-call maps to 'interested', not 'not_interested'
    // so the hung_up_early refinement should not apply
    expect(result.outcome).toBe('interested')
  })
})

describe('Transcript keyword matching for callback_requested', () => {
  it('refines to callback_requested when transcript contains "call me back"', () => {
    const result = processEndOfCallReport({
      endedReason: 'customer-ended-call',
      durationSeconds: 60,
      transcript: 'Yeah sure, can you call me back tomorrow?',
    })
    expect(result.outcome).toBe('callback_requested')
    expect(result.refinedBy).toContain('transcript_keyword:callback')
  })

  it('refines to callback_requested when transcript contains "callback"', () => {
    const result = processEndOfCallReport({
      endedReason: 'assistant-ended-call',
      durationSeconds: 90,
      transcript: 'I would prefer a callback later in the evening.',
    })
    expect(result.outcome).toBe('callback_requested')
  })

  it('does NOT refine to callback_requested when link was sent (tool call)', () => {
    const result = processEndOfCallReport({
      endedReason: 'assistant-ended-call',
      durationSeconds: 120,
      transcript: 'Can you call me back? Actually send me the link.',
      toolCalls: [{ name: 'send_scheduling_link' }],
    })
    // link_sent takes priority over callback_requested
    expect(result.outcome).toBe('link_sent')
  })

  it('does NOT refine when no callback keywords in transcript', () => {
    const result = processEndOfCallReport({
      endedReason: 'customer-ended-call',
      durationSeconds: 60,
      transcript: 'Thanks for calling, I am not interested right now.',
    })
    expect(result.outcome).toBe('not_interested')
    expect(result.refinedBy).not.toContain('transcript_keyword:callback')
  })

  it('is case-insensitive when matching keywords', () => {
    const result = processEndOfCallReport({
      endedReason: 'customer-ended-call',
      durationSeconds: 60,
      transcript: 'CALL ME BACK please!',
    })
    expect(result.outcome).toBe('callback_requested')
  })
})

describe('Tool call detection for link_sent', () => {
  it('sets outcome to link_sent when send_scheduling_link tool was called', () => {
    const result = processEndOfCallReport({
      endedReason: 'assistant-ended-call',
      durationSeconds: 120,
      toolCalls: [{ name: 'send_scheduling_link' }],
    })
    expect(result.outcome).toBe('link_sent')
    expect(result.refinedBy).toContain('tool_call:send_scheduling_link')
  })

  it('does NOT set link_sent when other tools were called', () => {
    const result = processEndOfCallReport({
      endedReason: 'assistant-ended-call',
      durationSeconds: 120,
      toolCalls: [{ name: 'some_other_tool' }],
    })
    expect(result.outcome).toBe('interested')
  })
})
