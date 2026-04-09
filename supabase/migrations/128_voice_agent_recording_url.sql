-- Add recording_url column to voice_agent_logs for Vapi call recordings
ALTER TABLE voice_agent_logs ADD COLUMN IF NOT EXISTS recording_url TEXT;
