-- Migration: Add GLB file URL to project_measurements
-- GLB format is needed for React Three Fiber web viewer (3D in browser)
-- USDZ remains for iOS AR Quick Look compatibility

-- Add glb_file_url column to store converted GLB models
ALTER TABLE project_measurements
ADD COLUMN IF NOT EXISTS glb_file_url TEXT;

-- Add comment explaining the column
COMMENT ON COLUMN project_measurements.glb_file_url IS
'URL to GLB version of 3D model for web browser viewing. Converted from USDZ or exported directly from RoomPlan.';

-- Index for quick lookups when filtering projects with 3D models
CREATE INDEX IF NOT EXISTS idx_project_measurements_glb_file_url
ON project_measurements(glb_file_url)
WHERE glb_file_url IS NOT NULL;
