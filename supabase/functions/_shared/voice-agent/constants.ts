// Voice Agent constants, outcome mappings, and default configurations

import type { SimplifiedOutcome, PostCallFlow } from './types.ts'

export const DEFAULT_SMS_TEMPLATE = `Hi {{customer_first_name}}, this is {{showroom_name}}! Thank you for submitting your project (Ref: {{reference_number}}). We'd love to help bring your vision to life. We'll give you a quick call shortly to schedule your showroom visit.`

export const DEFAULT_SYSTEM_PROMPT = `You are a friendly scheduling assistant calling on behalf of {{showroom_name}}. {{customer_full_name}} recently submitted a project (Ref: {{reference_number}}) and received an SMS from this number. Your goal is to schedule a showroom visit. Introduce yourself, reference their project, offer scheduling options, keep it under 2 minutes, never discuss pricing. If interested, use the send_scheduling_link tool to text them a booking link.`

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

// Maps real Vapi `endedReason` enum values → our simplified business outcomes
// All keys here are validated against Vapi's official CallEndedReason enum
export const VAPI_OUTCOME_MAP: Record<string, SimplifiedOutcome> = {
  // Customer didn't answer
  'customer-did-not-answer': 'no_answer',

  // Customer's line was busy
  'customer-busy': 'line_busy',

  // Voicemail picked up
  'voicemail': 'voicemail',

  // Customer didn't speak (silence timeout)
  'silence-timed-out': 'ghosted',

  // Assistant successfully completed the call (positive outcome)
  'assistant-ended-call': 'interested',
  'assistant-said-end-call-phrase': 'interested',
  'assistant-ended-call-after-message-spoken': 'interested',
  'assistant-ended-call-with-hangup-task': 'interested',

  // Customer hung up the call
  'customer-ended-call': 'not_interested',
  'customer-ended-call-before-warm-transfer': 'not_interested',
  'customer-ended-call-after-warm-transfer-attempt': 'not_interested',
  'customer-ended-call-during-transfer': 'not_interested',

  // Customer didn't give microphone permission (hung up before talking)
  'customer-did-not-give-microphone-permission': 'hung_up_early',

  // Misc — treat as technical error
  'assistant-join-timed-out': 'technical_error',
  'exceeded-max-duration': 'technical_error',
  'manually-canceled': 'technical_error',
  'phone-call-provider-closed-websocket': 'technical_error',
  'twilio-failed-to-connect-call': 'technical_error',
  'twilio-reported-customer-misdialed': 'technical_error',
  'vonage-rejected': 'technical_error',
  'vonage-failed-to-connect-call': 'technical_error',
  'worker-shutdown': 'technical_error',
  'call-deleted': 'technical_error',
}

export function mapVapiOutcome(endedReason: string): SimplifiedOutcome {
  if (VAPI_OUTCOME_MAP[endedReason]) {
    return VAPI_OUTCOME_MAP[endedReason]
  }

  // Vapi error prefixes — all map to technical_error
  if (
    endedReason.startsWith('error-') ||
    endedReason.startsWith('pipeline-error-') ||
    endedReason.startsWith('call.in-progress.error-') ||
    endedReason.startsWith('call.start.error-') ||
    endedReason.startsWith('call.ringing.error-') ||
    endedReason.startsWith('call.ending.error-') ||
    endedReason.startsWith('assistant-request-')
  ) {
    return 'technical_error'
  }

  return 'technical_error'
}

export const DEFAULT_POST_CALL_FLOW: PostCallFlow = {
  nodes: [
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
    { id: 'na_wait', type: 'wait', data: { mode: 'next_business_day', hours: 24 }, position: { x: 300, y: 0 } },
    { id: 'na_retry', type: 'retry_call', data: { maxAttempts: 3 }, position: { x: 550, y: 0 } },
    { id: 'na_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, we tried reaching you about your project at {{showroom_name}}. Call us at {{showroom_phone}} or book a visit: {{scheduling_link}}' }, position: { x: 800, y: 50 } },
    { id: 'na_stop', type: 'stop', data: {}, position: { x: 1050, y: 50 } },
    { id: 'lb_wait', type: 'wait', data: { hours: 1 }, position: { x: 300, y: 150 } },
    { id: 'lb_retry', type: 'retry_call', data: { maxAttempts: 3 }, position: { x: 550, y: 150 } },
    { id: 'lb_stop', type: 'stop', data: {}, position: { x: 800, y: 150 } },
    { id: 'vm_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, we left you a voicemail about your project at {{showroom_name}}. Book your showroom visit here: {{scheduling_link}}' }, position: { x: 300, y: 300 } },
    { id: 'vm_stop', type: 'stop', data: {}, position: { x: 600, y: 300 } },
    { id: 'gh_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, sorry we missed you! When you are ready to discuss your project at {{showroom_name}}, book a visit: {{scheduling_link}}' }, position: { x: 300, y: 450 } },
    { id: 'gh_stop', type: 'stop', data: {}, position: { x: 600, y: 450 } },
    { id: 'int_sms', type: 'sms', data: { template: "Here's your link to schedule a visit: {{scheduling_link}}" }, position: { x: 300, y: 600 } },
    { id: 'int_stop', type: 'stop', data: {}, position: { x: 600, y: 600 } },
    { id: 'ni_stop', type: 'stop', data: {}, position: { x: 300, y: 750 } },
    { id: 'ls_stop', type: 'stop', data: {}, position: { x: 300, y: 900 } },
    { id: 'cb_wait', type: 'wait', data: { hours: 4 }, position: { x: 300, y: 1050 } },
    { id: 'cb_retry', type: 'retry_call', data: { maxAttempts: 2 }, position: { x: 550, y: 1050 } },
    { id: 'cb_stop', type: 'stop', data: {}, position: { x: 800, y: 1050 } },
    { id: 'hu_sms', type: 'sms', data: { template: 'Hi {{customer_first_name}}, this is {{showroom_name}}. We just tried calling about your project. Book a visit at your convenience: {{scheduling_link}}' }, position: { x: 300, y: 1200 } },
    { id: 'hu_stop', type: 'stop', data: {}, position: { x: 600, y: 1200 } },
    { id: 'te_retry', type: 'retry_call', data: { maxAttempts: 1 }, position: { x: 300, y: 1350 } },
    { id: 'te_stop', type: 'stop', data: {}, position: { x: 550, y: 1350 } },
  ],
  edges: [
    { source: 'no_answer', target: 'na_wait' },
    { source: 'na_wait', target: 'na_retry' },
    { source: 'na_retry', target: 'na_sms', sourceHandle: 'max_reached' },
    { source: 'na_sms', target: 'na_stop' },
    { source: 'line_busy', target: 'lb_wait' },
    { source: 'lb_wait', target: 'lb_retry' },
    { source: 'lb_retry', target: 'lb_stop', sourceHandle: 'max_reached' },
    { source: 'voicemail', target: 'vm_sms' },
    { source: 'vm_sms', target: 'vm_stop' },
    { source: 'ghosted', target: 'gh_sms' },
    { source: 'gh_sms', target: 'gh_stop' },
    { source: 'interested', target: 'int_sms' },
    { source: 'int_sms', target: 'int_stop' },
    { source: 'not_interested', target: 'ni_stop' },
    { source: 'link_sent', target: 'ls_stop' },
    { source: 'callback_requested', target: 'cb_wait' },
    { source: 'cb_wait', target: 'cb_retry' },
    { source: 'cb_retry', target: 'cb_stop', sourceHandle: 'max_reached' },
    { source: 'hung_up_early', target: 'hu_sms' },
    { source: 'hu_sms', target: 'hu_stop' },
    { source: 'technical_error', target: 'te_retry' },
    { source: 'te_retry', target: 'te_stop', sourceHandle: 'max_reached' },
  ],
}

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
    url: '',
  },
}
