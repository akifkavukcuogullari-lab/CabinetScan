-- Allow all authenticated users to read non-secret platform settings
-- (e.g., voice_agent_globally_enabled toggle)
-- Secret settings (API keys) remain restricted to super admins only
CREATE POLICY "platform_settings_select_authenticated_non_secret"
  ON platform_settings FOR SELECT
  TO authenticated
  USING (is_secret = false);
