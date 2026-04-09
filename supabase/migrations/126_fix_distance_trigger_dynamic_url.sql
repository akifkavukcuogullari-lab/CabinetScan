-- Fix: Use dynamic supabase_url from system_config instead of hardcoded QA URL
-- This makes the trigger work across all environments (QA + production)

CREATE OR REPLACE FUNCTION trigger_calculate_project_distance()
RETURNS TRIGGER AS $$
DECLARE
  supabase_url TEXT;
  service_role_key TEXT;
BEGIN
  IF NEW.end_client_address IS NOT NULL AND NEW.end_client_address != '' THEN
    SELECT value INTO supabase_url FROM system_config WHERE key = 'supabase_url';
    SELECT value INTO service_role_key FROM system_config WHERE key = 'service_role_key';

    IF supabase_url IS NOT NULL AND service_role_key IS NOT NULL THEN
      PERFORM net.http_post(
        url := supabase_url || '/functions/v1/calculate-project-distance',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || service_role_key
        ),
        body := jsonb_build_object('project_id', NEW.id)
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
