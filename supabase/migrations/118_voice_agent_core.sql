-- =============================================================================
-- 118_voice_agent_core.sql
-- Voice Agent core tables: platform_settings, voice_agent_showroom_settings,
-- voice_agent_logs
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Reusable updated_at trigger function
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ===========================================================================
-- 1. platform_settings — key-value config store for super admin
-- ===========================================================================
CREATE TABLE platform_settings (
  key TEXT PRIMARY KEY,
  value TEXT,
  description TEXT,
  is_secret BOOLEAN DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE platform_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "platform_settings_select_super_admin"
  ON platform_settings FOR SELECT
  USING (is_super_admin());

CREATE POLICY "platform_settings_update_super_admin"
  ON platform_settings FOR UPDATE
  USING (is_super_admin());

CREATE TRIGGER set_platform_settings_updated_at
  BEFORE UPDATE ON platform_settings
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Seed default rows
INSERT INTO platform_settings (key, value, description, is_secret) VALUES
  ('voice_agent_globally_enabled', 'false', 'Master on/off switch for voice agent', false),
  ('vapi_api_key', '', 'Vapi.ai API key', true),
  ('vapi_phone_number_id', '', 'Shared Vapi phone number ID', false),
  ('twilio_account_sid', '', 'Twilio account SID', true),
  ('twilio_auth_token', '', 'Twilio auth token', true),
  ('twilio_phone_number', '', 'Shared Twilio phone number (E.164)', false),
  ('google_maps_api_key', '', 'Google Maps Distance Matrix API key', true),
  ('va_default_sms_template', 'Hi {{customer_first_name}}, this is {{showroom_name}}! Thank you for submitting your project (Ref: {{reference_number}}). We''d love to help bring your vision to life. We''ll give you a quick call shortly to schedule your showroom visit.', 'Master default SMS template', false),
  ('va_default_system_prompt', 'You are a friendly scheduling assistant calling on behalf of {{showroom_name}}. {{customer_full_name}} recently submitted a project (Ref: {{reference_number}}) and received an SMS from this number. Your goal is to schedule a showroom visit. Introduce yourself, reference their project, offer scheduling options, keep it under 2 minutes, never discuss pricing. If interested, use the send_scheduling_link tool to text them a booking link.', 'Master default voice system prompt', false);

-- ===========================================================================
-- 2. voice_agent_showroom_settings — per-showroom voice agent config
-- ===========================================================================
CREATE TABLE voice_agent_showroom_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  showroom_id UUID NOT NULL UNIQUE REFERENCES showrooms(id) ON DELETE CASCADE,
  enabled BOOLEAN DEFAULT false,
  trigger_mode TEXT DEFAULT 'manual' CHECK (trigger_mode IN ('immediate', 'delayed', 'manual')),
  delay_minutes INTEGER DEFAULT 5,
  distance_threshold_miles INTEGER DEFAULT 50,
  scheduling_link TEXT,
  near_homeowner_sms_template TEXT,
  near_homeowner_system_prompt TEXT,
  near_contractor_sms_template TEXT,
  near_contractor_system_prompt TEXT,
  far_homeowner_sms_template TEXT,
  far_homeowner_system_prompt TEXT,
  far_contractor_sms_template TEXT,
  far_contractor_system_prompt TEXT,
  post_call_flow JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE voice_agent_showroom_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "va_showroom_settings_select"
  ON voice_agent_showroom_settings FOR SELECT
  USING (is_super_admin() OR has_showroom_access(showroom_id));

CREATE POLICY "va_showroom_settings_insert"
  ON voice_agent_showroom_settings FOR INSERT
  WITH CHECK (is_super_admin() OR has_showroom_access(showroom_id));

CREATE POLICY "va_showroom_settings_update"
  ON voice_agent_showroom_settings FOR UPDATE
  USING (is_super_admin() OR has_showroom_access(showroom_id));

CREATE POLICY "va_showroom_settings_delete"
  ON voice_agent_showroom_settings FOR DELETE
  USING (is_super_admin());

CREATE TRIGGER set_va_showroom_settings_updated_at
  BEFORE UPDATE ON voice_agent_showroom_settings
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ===========================================================================
-- 3. voice_agent_logs — every SMS + call attempt
-- ===========================================================================
CREATE TABLE voice_agent_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  customer_phone TEXT,
  -- SMS fields
  sms_status TEXT DEFAULT 'pending',
  sms_sid TEXT,
  sms_sent_at TIMESTAMPTZ,
  sms_error TEXT,
  -- Call fields
  call_status TEXT DEFAULT 'pending',
  vapi_call_id TEXT,
  vapi_ended_reason TEXT,
  call_scheduled_at TIMESTAMPTZ,
  call_started_at TIMESTAMPTZ,
  call_ended_at TIMESTAMPTZ,
  call_duration_seconds INTEGER,
  call_error TEXT,
  -- Outcome fields
  outcome TEXT,
  outcome_details JSONB,
  call_summary TEXT,
  call_transcript TEXT,
  -- Distance fields
  distance_miles DECIMAL(8,2),
  drive_time_minutes INTEGER,
  distance_zone TEXT,
  customer_type_used TEXT,
  -- Flow fields
  attempt_number INTEGER DEFAULT 1,
  flow_status TEXT DEFAULT 'active',
  flow_current_node TEXT,
  flow_next_at TIMESTAMPTZ,
  -- Meta
  trigger_mode TEXT,
  triggered_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE voice_agent_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "va_logs_select"
  ON voice_agent_logs FOR SELECT
  USING (is_super_admin() OR has_showroom_access(showroom_id));

CREATE POLICY "va_logs_insert"
  ON voice_agent_logs FOR INSERT
  WITH CHECK (is_super_admin() OR has_showroom_access(showroom_id));

CREATE POLICY "va_logs_update"
  ON voice_agent_logs FOR UPDATE
  USING (is_super_admin() OR has_showroom_access(showroom_id));

CREATE POLICY "va_logs_delete"
  ON voice_agent_logs FOR DELETE
  USING (is_super_admin());

-- Indexes for common queries
CREATE INDEX idx_va_logs_project_id ON voice_agent_logs(project_id);
CREATE INDEX idx_va_logs_showroom_id ON voice_agent_logs(showroom_id);
CREATE INDEX idx_va_logs_call_status ON voice_agent_logs(call_status);
CREATE INDEX idx_va_logs_flow_status_next ON voice_agent_logs(flow_status, flow_next_at);

CREATE TRIGGER set_va_logs_updated_at
  BEFORE UPDATE ON voice_agent_logs
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
