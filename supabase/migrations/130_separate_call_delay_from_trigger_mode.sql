-- Separate call delay from trigger mode
-- trigger_mode: only 'immediate' or 'manual' (when to fire)
-- delay_minutes: independent delay between SMS and call (applies to both modes)

-- Update any 'delayed' rows to 'immediate' (they already have delay_minutes set)
UPDATE voice_agent_showroom_settings
SET trigger_mode = 'immediate'
WHERE trigger_mode = 'delayed';

-- Drop old check constraint and add new one
ALTER TABLE voice_agent_showroom_settings
  DROP CONSTRAINT IF EXISTS voice_agent_showroom_settings_trigger_mode_check;

ALTER TABLE voice_agent_showroom_settings
  ADD CONSTRAINT voice_agent_showroom_settings_trigger_mode_check
  CHECK (trigger_mode IN ('immediate', 'manual'));

-- Set delay_minutes default to 0 (no delay) for new rows
ALTER TABLE voice_agent_showroom_settings
  ALTER COLUMN delay_minutes SET DEFAULT 0;
