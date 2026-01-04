-- ============================================
-- DROP GLB FILE URL COLUMN
-- Removes deprecated GLB 3D model column (web 3D viewing is deprecated)
-- USDZ files remain for iOS AR Quick Look
-- ============================================

-- Drop the index first
DROP INDEX IF EXISTS idx_project_measurements_glb_file_url;

-- Drop the column
ALTER TABLE project_measurements
DROP COLUMN IF EXISTS glb_file_url;
