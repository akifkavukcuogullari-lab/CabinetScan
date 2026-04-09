// =============================================================================
// Voice Agent Types — Backend (Deno Edge Functions)
// =============================================================================

// Platform Settings
export interface PlatformSetting {
  key: string
  value: string | null
  description: string | null
  is_secret: boolean
  updated_at: string
}

// Showroom Settings
export interface VoiceAgentShowroomSettings {
  id: string
  showroom_id: string
  enabled: boolean
  trigger_mode: 'immediate' | 'delayed' | 'manual'
  delay_minutes: number
  distance_threshold_miles: number
  scheduling_link: string | null
  near_homeowner_sms_template: string | null
  near_homeowner_system_prompt: string | null
  near_contractor_sms_template: string | null
  near_contractor_system_prompt: string | null
  far_homeowner_sms_template: string | null
  far_homeowner_system_prompt: string | null
  far_contractor_sms_template: string | null
  far_contractor_system_prompt: string | null
  post_call_flow: PostCallFlow | null
  created_at: string
  updated_at: string
}

// Voice Agent Log
export interface VoiceAgentLog {
  id: string
  showroom_id: string
  project_id: string
  customer_id: string | null
  customer_phone: string | null
  sms_status: string
  sms_sid: string | null
  sms_sent_at: string | null
  sms_error: string | null
  call_status: string
  vapi_call_id: string | null
  vapi_ended_reason: string | null
  call_scheduled_at: string | null
  call_started_at: string | null
  call_ended_at: string | null
  call_duration_seconds: number | null
  call_error: string | null
  outcome: SimplifiedOutcome | null
  outcome_details: Record<string, unknown> | null
  call_summary: string | null
  call_transcript: string | null
  distance_miles: number | null
  drive_time_minutes: number | null
  distance_zone: 'near' | 'far' | null
  customer_type_used: 'homeowner' | 'contractor' | null
  attempt_number: number
  flow_status: 'active' | 'waiting' | 'completed' | 'stopped'
  flow_current_node: string | null
  flow_next_at: string | null
  trigger_mode: string | null
  triggered_by: string | null
  created_at: string
  updated_at: string
}

// Trigger Payload (webhook contract)
export interface VoiceAgentTriggerPayload {
  project_id: string
  showroom_id: string
  customer: {
    id: string
    first_name: string
    last_name: string
    phone_normalized: string
    email: string | null
    customer_type: 'homeowner' | 'contractor'
    address_line1: string | null
    city: string | null
    state: string | null
    zip_code: string | null
  }
  end_client: {
    first_name: string | null
    last_name: string | null
    phone: string | null
    email: string | null
    address: string | null
  }
  project: {
    name: string
    reference_number: string
    notes: string | null
    status: string
    submitted_at: string
  }
  showroom: {
    name: string
    phone: string | null
    email: string | null
    address_line1: string | null
    city: string | null
    state: string | null
    postal_code: string | null
    showroom_code: string
  }
  triggered_by: string
}

// Template Variables
export interface TemplateVariables {
  customer_first_name: string
  customer_last_name: string
  customer_full_name: string
  customer_phone: string
  customer_email: string
  customer_type: string
  customer_address: string
  customer_city: string
  customer_state: string
  customer_zip: string
  end_client_first_name: string
  end_client_last_name: string
  end_client_phone: string
  end_client_email: string
  end_client_address: string
  project_name: string
  reference_number: string
  project_notes: string
  project_status: string
  submitted_at: string
  showroom_name: string
  showroom_phone: string
  showroom_email: string
  showroom_address: string
  showroom_city: string
  showroom_state: string
  showroom_code: string
  distance_miles: string
  distance_km: string
  drive_time: string
  distance_zone: string
}

// Simplified Outcomes
export type SimplifiedOutcome =
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

// Flow Types
export type FlowNodeType = 'outcome' | 'wait' | 'sms' | 'retry_call' | 'send_link' | 'condition' | 'stop'

export interface FlowNode {
  id: string
  type: FlowNodeType
  data: Record<string, unknown>
  position: { x: number; y: number }
}

export interface FlowEdge {
  id?: string
  source: string
  target: string
  sourceHandle?: string
}

export interface PostCallFlow {
  nodes: FlowNode[]
  edges: FlowEdge[]
}

// Distance Result
export interface DistanceResult {
  distanceMiles: number
  distanceKm: number
  driveTimeMinutes: number
  zone: 'near' | 'far'
}
