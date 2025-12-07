-- Add visualization_photo_url column to project_measurements table
-- This stores the wide-angle corner photo taken after room scan

ALTER TABLE project_measurements
ADD COLUMN IF NOT EXISTS visualization_photo_url TEXT;

-- Add comment for documentation
COMMENT ON COLUMN project_measurements.visualization_photo_url IS 'URL of wide-angle visualization photo taken from kitchen corner';
