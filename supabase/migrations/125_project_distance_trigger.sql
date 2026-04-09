-- Enable pg_net extension for HTTP requests from triggers
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Function that calls the calculate-project-distance Edge Function
-- Reads service role key from Supabase Vault (secret name: 'service_role_key')
CREATE OR REPLACE FUNCTION trigger_calculate_project_distance()
RETURNS TRIGGER AS $$
DECLARE
  _key TEXT;
BEGIN
  IF NEW.end_client_address IS NOT NULL AND NEW.end_client_address != '' THEN
    -- Read service role key from vault
    SELECT decrypted_secret INTO _key
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key'
    LIMIT 1;

    IF _key IS NOT NULL THEN
      PERFORM net.http_post(
        url := 'https://wnyrnpeabhxdqvcpofmb.supabase.co/functions/v1/calculate-project-distance',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || _key
        ),
        body := jsonb_build_object('project_id', NEW.id)
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on INSERT (new project) and UPDATE of end_client_address
CREATE TRIGGER project_distance_on_create
  AFTER INSERT ON projects
  FOR EACH ROW
  EXECUTE FUNCTION trigger_calculate_project_distance();

CREATE TRIGGER project_distance_on_address_update
  AFTER UPDATE OF end_client_address ON projects
  FOR EACH ROW
  WHEN (OLD.end_client_address IS DISTINCT FROM NEW.end_client_address)
  EXECUTE FUNCTION trigger_calculate_project_distance();
