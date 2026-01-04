-- ============================================
-- NEXTLEAN SCAN - ARCHIVE CRON CONFIG TABLE
-- Migration: 066_archive_cron_config_table
-- Purpose: Add config table for cron job credentials
-- ============================================

-- Create config table for storing Edge Function credentials
CREATE TABLE IF NOT EXISTS system_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Only super admins can access this table
ALTER TABLE system_config ENABLE ROW LEVEL SECURITY;

-- Drop existing policy if exists and recreate
DROP POLICY IF EXISTS "Super admins can manage system config" ON system_config;
CREATE POLICY "Super admins can manage system config"
ON system_config
FOR ALL
TO authenticated
USING (is_super_admin())
WITH CHECK (is_super_admin());

-- Insert the Supabase URL (service key will be added manually for security)
INSERT INTO system_config (key, value) VALUES
    ('supabase_url', 'https://wnyrnpeabhxdqvcpofmb.supabase.co')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- Update function to use config table
CREATE OR REPLACE FUNCTION call_archive_edge_function()
RETURNS void AS $$
DECLARE
  supabase_url TEXT;
  service_role_key TEXT;
BEGIN
  -- Get configuration from system_config table
  SELECT value INTO supabase_url FROM system_config WHERE key = 'supabase_url';
  SELECT value INTO service_role_key FROM system_config WHERE key = 'service_role_key';

  -- If settings not available, skip
  IF supabase_url IS NULL OR service_role_key IS NULL THEN
    RAISE NOTICE 'Supabase configuration not complete, skipping Edge Function call. Add service_role_key to system_config.';
    RETURN;
  END IF;

  -- Call the archive-project-files Edge Function with batch mode
  PERFORM net.http_post(
    url := supabase_url || '/functions/v1/archive-project-files',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_role_key
    ),
    body := '{"batch": true}'::jsonb
  );

  RAISE NOTICE 'Archive Edge Function called at %', NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update re-archive function
CREATE OR REPLACE FUNCTION call_rearchive_edge_function()
RETURNS void AS $$
DECLARE
  supabase_url TEXT;
  service_role_key TEXT;
  expired_projects RECORD;
BEGIN
  SELECT value INTO supabase_url FROM system_config WHERE key = 'supabase_url';
  SELECT value INTO service_role_key FROM system_config WHERE key = 'service_role_key';

  IF supabase_url IS NULL OR service_role_key IS NULL THEN
    RAISE NOTICE 'Supabase configuration not complete, skipping re-archive';
    RETURN;
  END IF;

  -- Find projects with expired restore window
  FOR expired_projects IN
    SELECT id FROM projects
    WHERE storage_tier = 'hot'
      AND restore_available_until IS NOT NULL
      AND restore_available_until < NOW()
  LOOP
    -- Call archive for each expired project
    PERFORM net.http_post(
      url := supabase_url || '/functions/v1/archive-project-files',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key
      ),
      body := jsonb_build_object('project_id', expired_projects.id)
    );

    RAISE NOTICE 'Re-archiving project % after restore expiry', expired_projects.id;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add documentation
COMMENT ON TABLE system_config IS 'System configuration for internal operations. Add service_role_key manually for cron jobs.';
