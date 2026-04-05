// Voice Agent constants, outcome mappings, and default configurations

import type { SimplifiedOutcome, PostCallFlow } from '../types/index.ts'

// ---------------------------------------------------------------------------
// Default SMS template (same as seeded in platform_settings)
// ---------------------------------------------------------------------------
export const DEFAULT_SMS_TEMPLATE = `Hi {{customer_first_name}}, this is {{showroom_name}}! Thank you for submitting your project (Ref: {{reference_number}}). We'd love to help bring your vision to life. We'll give you a quick call shortly to schedule your showroom visit.`

// ---------------------------------------------------------------------------
// Default system prompt for the Vapi assistant (same as seeded)
// ---------------------------------------------------------------------------
export const DEFAULT_SYSTEM_PROMPT = `You are a friendly scheduling assistant calling on behalf of {{showroom_name}}. {{customer_full_name}} recently submitted a project (Ref: {{reference_number}}) and received an SMS from this number. Your goal is to schedule a showroom visit. Introduce yourself, reference their project, offer scheduling options, keep it under 2 minutes, never discuss pricing. If interested, use the send_scheduling_link tool to text them a booking link.`

// ---------------------------------------------------------------------------
// All possible simplified outcome values
// ---------------------------------------------------------------------------
export const SIMPLIFIED_OUTCOMES: SimplifiedOutcome[] = [
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

// ---------------------------------------------------------------------------
// Vapi endedReason -> SimplifiedOutcome mapping
// ---------------------------------------------------------------------------
export const VAPI_OUTCOME_MAP: Record<string, SimplifiedOutcome> = {
  // No Answer
  'customer-did-not-answer': 'no_answer',
  'no-answer': 'no_answer',

  // Line Busy
  'customer-busy': 'line_busy',
  'busy': 'line_busy',

  // Voicemail
  'voicemail': 'voicemail',
  'machine-detected': 'voicemail',

  // Ghosted (picked up but silent)
  'silence-timed-out': 'ghosted',

  // Normal call endings (defaults -- webhook refines via transcript analysis)
  'assistant-ended-call': 'interested',
  'customer-ended-call': 'not_interested',

  // Hung up early
  'customer-did-not-give-microphone-permission': 'hung_up_early',

  // Technical errors
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

/**
 * Map a Vapi endedReason string to a SimplifiedOutcome.
 * Checks exact match first, then prefix patterns, then falls back to technical_error.
 */
export function mapVapiOutcome(endedReason: string): SimplifiedOutcome {
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

// ---------------------------------------------------------------------------
// Default post-call flow configuration (visual flow builder default state)
// ---------------------------------------------------------------------------
export const DEFAULT_POST_CALL_FLOW: PostCallFlow = {
  nodes: [
    // ---- Outcome nodes (pre-placed, cannot be deleted) ----
    { id: 'no_answer', type: 'outcome', data: { outcome: 'no_answer', label: 'No Answer' }, position: { x: 0, y: 0 } },
    { id: 'line_busy', type: 'outcome', data: { outcome: 'line_busy', label: 'Line Busy' }, position: { x: 0, y: 150 } },
    { id: 'voicemail', type: 'outcome', data: { outcome: 'voicemail', label: 'Voicemail' }, position: { x: 0, y: 300 } },
    { id: 'ghosted', type: 'outcome', data: { outcome: 'ghosted', label: 'Ghosted' }, position: { x: 0, y: 450 } },
    { id: 'interested', type: 'outcome', data: { outcome: 'interested', label: 'Interested' }, position: { x: 0, y: 600 } },
    { id: 'not_interested', type: 'outcome', data: { outcome: 'not_interested', label: 'Not Interested' }, position: { x: 0, y: 750 } },
    { id: 'link_sent', type: 'outcome', data: { outcome: 'link_sent', label: 'Link Sent' }, position: { x: 0, y: 900 } },
    { id: 'callback_requested', type: 'outcome', data: { outcome: 'callback_requested', label: 'Callback Requested' }, position: { x: 0, y: 1050 } },
    { id: 'hung_up_early', type: 'outcome', data: { outcome: 'hung_up_early', label: 'Hung Up Early' }, position: { x: 0, y: 1200 } },
    { id: 'technical_error', type: 'outcome', data: { outcome: 'technical_error', label: 'Technical Error' }, position: { x: 0, y: 1350 } },

    // ---- No Answer flow: Wait 24h -> Retry (max 3) -> SMS -> Stop ----
    { id: 'na_wait', type: 'wait', data: { hours: 24 }, position: { x: 300, y: 0 } },
    { id: 'na_retry', type: 'retry_call', data: { maxAttempts: 3 }, position: { x: 550, y: 0 } },
    { id: 'na_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, we tried reaching you about your project at {{showroom_name}}. Feel free to call us at {{showroom_phone}} or book a visit: {{scheduling_link}}' }, position: { x: 800, y: 50 } },
    { id: 'na_stop', type: 'stop', data: {}, position: { x: 1050, y: 50 } },

    // ---- Line Busy flow: Wait 1h -> Retry (max 3) -> SMS -> Stop ----
    { id: 'lb_wait', type: 'wait', data: { hours: 1 }, position: { x: 300, y: 150 } },
    { id: 'lb_retry', type: 'retry_call', data: { maxAttempts: 3 }, position: { x: 550, y: 150 } },
    { id: 'lb_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, we tried calling about your project at {{showroom_name}}. Call us at {{showroom_phone}} or book online: {{scheduling_link}}' }, position: { x: 800, y: 200 } },
    { id: 'lb_stop', type: 'stop', data: {}, position: { x: 1050, y: 200 } },

    // ---- Voicemail flow: SMS + link -> Wait 48h -> Retry (max 2) -> Stop ----
    { id: 'vm_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, we left you a voicemail about your project at {{showroom_name}}. Book your showroom visit here: {{scheduling_link}}' }, position: { x: 300, y: 300 } },
    { id: 'vm_wait', type: 'wait', data: { hours: 48 }, position: { x: 550, y: 300 } },
    { id: 'vm_retry', type: 'retry_call', data: { maxAttempts: 2 }, position: { x: 800, y: 300 } },
    { id: 'vm_stop', type: 'stop', data: {}, position: { x: 1050, y: 300 } },

    // ---- Ghosted flow: SMS -> Stop ----
    { id: 'gh_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, sorry we missed you! When you are ready to discuss your project at {{showroom_name}}, book a visit: {{scheduling_link}}' }, position: { x: 300, y: 450 } },
    { id: 'gh_stop', type: 'stop', data: {}, position: { x: 550, y: 450 } },

    // ---- Interested flow: Send scheduling link -> Stop ----
    { id: 'int_link', type: 'send_link', data: {}, position: { x: 300, y: 600 } },
    { id: 'int_stop', type: 'stop', data: {}, position: { x: 550, y: 600 } },

    // ---- Not Interested flow: Stop ----
    { id: 'ni_stop', type: 'stop', data: {}, position: { x: 300, y: 750 } },

    // ---- Link Sent flow: Stop ----
    { id: 'ls_stop', type: 'stop', data: {}, position: { x: 300, y: 900 } },

    // ---- Callback Requested: Wait 4h -> Retry (max 2) -> Stop ----
    { id: 'cb_wait', type: 'wait', data: { hours: 4 }, position: { x: 300, y: 1050 } },
    { id: 'cb_retry', type: 'retry_call', data: { maxAttempts: 2 }, position: { x: 550, y: 1050 } },
    { id: 'cb_stop', type: 'stop', data: {}, position: { x: 800, y: 1050 } },

    // ---- Hung Up Early: Wait 2h -> SMS + link -> Stop ----
    { id: 'hu_wait', type: 'wait', data: { hours: 2 }, position: { x: 300, y: 1200 } },
    { id: 'hu_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, this is {{showroom_name}}. We just tried calling about your project. Book a visit at your convenience: {{scheduling_link}}' }, position: { x: 550, y: 1200 } },
    { id: 'hu_stop', type: 'stop', data: {}, position: { x: 800, y: 1200 } },

    // ---- Technical Error: Retry immediately (max 1) -> Stop ----
    { id: 'te_retry', type: 'retry_call', data: { maxAttempts: 1 }, position: { x: 300, y: 1350 } },
    { id: 'te_stop', type: 'stop', data: {}, position: { x: 550, y: 1350 } },
  ],
  edges: [
    // No Answer
    { source: 'no_answer', target: 'na_wait' },
    { source: 'na_wait', target: 'na_retry' },
    { source: 'na_retry', target: 'na_sms', sourceHandle: 'max_reached' },
    { source: 'na_sms', target: 'na_stop' },

    // Line Busy
    { source: 'line_busy', target: 'lb_wait' },
    { source: 'lb_wait', target: 'lb_retry' },
    { source: 'lb_retry', target: 'lb_sms', sourceHandle: 'max_reached' },
    { source: 'lb_sms', target: 'lb_stop' },

    // Voicemail
    { source: 'voicemail', target: 'vm_sms' },
    { source: 'vm_sms', target: 'vm_wait' },
    { source: 'vm_wait', target: 'vm_retry' },
    { source: 'vm_retry', target: 'vm_stop', sourceHandle: 'max_reached' },

    // Ghosted
    { source: 'ghosted', target: 'gh_sms' },
    { source: 'gh_sms', target: 'gh_stop' },

    // Interested
    { source: 'interested', target: 'int_link' },
    { source: 'int_link', target: 'int_stop' },

    // Not Interested
    { source: 'not_interested', target: 'ni_stop' },

    // Link Sent
    { source: 'link_sent', target: 'ls_stop' },

    // Callback Requested
    { source: 'callback_requested', target: 'cb_wait' },
    { source: 'cb_wait', target: 'cb_retry' },
    { source: 'cb_retry', target: 'cb_stop', sourceHandle: 'max_reached' },

    // Hung Up Early
    { source: 'hung_up_early', target: 'hu_wait' },
    { source: 'hu_wait', target: 'hu_sms' },
    { source: 'hu_sms', target: 'hu_stop' },

    // Technical Error
    { source: 'technical_error', target: 'te_retry' },
    { source: 'te_retry', target: 'te_stop', sourceHandle: 'max_reached' },
  ],
}

// ---------------------------------------------------------------------------
// Vapi send_scheduling_link tool definition (used in transient assistant)
// ---------------------------------------------------------------------------
export const SEND_LINK_TOOL_DEFINITION = {
  type: 'function' as const,
  function: {
    name: 'send_scheduling_link',
    description:
      'Send a scheduling link via SMS to the customer so they can book a showroom visit.',
    parameters: {
      type: 'object',
      properties: {},
      required: [],
    },
  },
  server: {
    // Will be set dynamically: ${SUPABASE_URL}/functions/v1/voice-agent-send-link
    url: '',
  },
}
