-- ============================================
-- NEXTLYN CABINET - PUSH NOTIFICATION SETUP
-- Migration: 112_push_notification_setup
-- Purpose: Push notifications for chat messages and design events.
--          A Postgres trigger on design_notifications calls the
--          send-push-notification Edge Function via pg_net.
--
-- DEPLOYMENT CHECKLIST (both QA and Production):
--   1. Apply this migration
--   2. Deploy edge functions:
--        supabase functions deploy send-push-notification
--        supabase functions deploy send-design-notification
--   3. Verify secrets exist:  APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID
-- ============================================

-- Optimized compound index for the Edge Function's push lookup
CREATE INDEX IF NOT EXISTS idx_device_tokens_push_lookup
    ON device_tokens (user_id, platform)
    WHERE is_active = true;

-- Allow showroom staff to update their project measurements (e.g., adding photos to scan row).
-- This does NOT affect CabinetScan — the customer app never updates measurements.
CREATE POLICY project_measurements_update ON project_measurements FOR UPDATE
    USING (EXISTS (SELECT 1 FROM projects p WHERE p.id = project_measurements.project_id AND has_showroom_access(p.showroom_id)))
    WITH CHECK (EXISTS (SELECT 1 FROM projects p WHERE p.id = project_measurements.project_id AND has_showroom_access(p.showroom_id)));

-- ============================================
-- TRIGGER: Send push notification on new design_notifications
-- When a row is inserted into design_notifications (by dashboard or iOS app),
-- this trigger calls the send-push-notification Edge Function via pg_net
-- to deliver APNs push to the recipient's iOS device.
-- Only fires for showroom recipients (iOS app users).
-- ============================================

CREATE OR REPLACE FUNCTION notify_push_on_design_notification()
RETURNS TRIGGER AS $$
DECLARE
  supabase_url TEXT;
  service_role_key TEXT;
BEGIN
  SELECT value INTO supabase_url FROM system_config WHERE key = 'supabase_url';
  SELECT value INTO service_role_key FROM system_config WHERE key = 'service_role_key';

  IF supabase_url IS NULL OR service_role_key IS NULL THEN
    RETURN NEW;
  END IF;

  -- Send push to showroom staff iOS devices
  IF NEW.recipient_type = 'showroom' THEN
    PERFORM net.http_post(
      url := supabase_url || '/functions/v1/send-push-notification',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key
      ),
      body := jsonb_build_object(
        'user_id', NEW.recipient_id,
        'title', 'Nextlyn Cabinet',
        'body', NEW.message,
        'data', jsonb_build_object(
          'type', NEW.event_type,
          'design_request_id', COALESCE(NEW.design_request_id::text, ''),
          'project_reference', COALESCE(NEW.project_reference, '')
        )
      )
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS design_notification_push_trigger ON design_notifications;
CREATE TRIGGER design_notification_push_trigger
    AFTER INSERT ON design_notifications
    FOR EACH ROW
    EXECUTE FUNCTION notify_push_on_design_notification();
