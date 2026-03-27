-- Add AI flow specific columns to project_measurements
-- These columns store data from the non-LiDAR (AI) capture flow

ALTER TABLE project_measurements ADD COLUMN IF NOT EXISTS poses_url TEXT;
ALTER TABLE project_measurements ADD COLUMN IF NOT EXISTS planes_url TEXT;
ALTER TABLE project_measurements ADD COLUMN IF NOT EXISTS scan_method TEXT DEFAULT 'lidar';
ALTER TABLE project_measurements ADD COLUMN IF NOT EXISTS ai_metadata JSONB;
ALTER TABLE project_measurements ADD COLUMN IF NOT EXISTS processing_job_id UUID REFERENCES processing_jobs(id);
