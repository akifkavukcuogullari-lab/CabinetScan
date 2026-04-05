-- Add distance columns to projects table
-- Calculated at project creation time using Google Maps API
ALTER TABLE projects ADD COLUMN IF NOT EXISTS distance_miles NUMERIC;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS drive_time_minutes INTEGER;
