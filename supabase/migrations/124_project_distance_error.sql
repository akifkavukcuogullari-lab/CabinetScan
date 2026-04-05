-- Add distance_error column to store address resolution failures
ALTER TABLE projects ADD COLUMN IF NOT EXISTS distance_error TEXT;
