-- Update visualization photos to support multiple URLs
-- Changes from single URL to array of URLs

-- Drop the old column
ALTER TABLE project_measurements
DROP COLUMN IF EXISTS visualization_photo_url;

-- Add new array column
ALTER TABLE project_measurements
ADD COLUMN IF NOT EXISTS visualization_photo_urls TEXT[] DEFAULT '{}';

-- Add comment for documentation
COMMENT ON COLUMN project_measurements.visualization_photo_urls IS 'Array of URLs for visualization photos taken from different angles (up to 5 photos)';
