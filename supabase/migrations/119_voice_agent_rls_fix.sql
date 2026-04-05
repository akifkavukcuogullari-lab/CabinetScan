-- Add missing INSERT policy for platform_settings (needed for upsert operations)
CREATE POLICY "platform_settings_insert_super_admin"
  ON platform_settings FOR INSERT
  WITH CHECK (is_super_admin());
