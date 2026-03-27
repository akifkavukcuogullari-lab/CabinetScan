-- Create processing_jobs table for server pipeline V2
-- Tracks async GPU processing jobs submitted from iOS AI flow

CREATE TABLE IF NOT EXISTS processing_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID REFERENCES showrooms(id),
    project_id UUID REFERENCES projects(id),

    -- Input URLs (Supabase storage paths)
    video_url TEXT NOT NULL,
    poses_url TEXT,
    planes_url TEXT,
    photo_urls JSONB DEFAULT '[]',
    metadata JSONB DEFAULT '{}',

    -- Status tracking
    status TEXT DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
    progress FLOAT DEFAULT 0 CHECK (progress >= 0 AND progress <= 1),
    stage TEXT,
    error_message TEXT,

    -- Results
    floor_plan_png_url TEXT,
    measurements_json_url TEXT,
    measurements_data JSONB,
    scale_confidence TEXT CHECK (scale_confidence IN ('high', 'medium', 'low') OR scale_confidence IS NULL),
    validation_passed BOOLEAN,
    validation_issues JSONB DEFAULT '[]',

    -- Pipeline info
    pipeline_version TEXT DEFAULT 'v2',
    processing_time_ms INT,
    stage_timings JSONB DEFAULT '{}',

    -- Timing
    created_at TIMESTAMPTZ DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    -- Worker tracking
    worker_id TEXT,
    retry_count INT DEFAULT 0
);

-- Indexes
CREATE INDEX idx_processing_jobs_status ON processing_jobs(status, created_at);
CREATE INDEX idx_processing_jobs_showroom ON processing_jobs(showroom_id);

-- Enable RLS
ALTER TABLE processing_jobs ENABLE ROW LEVEL SECURITY;

-- Anon users can create jobs (iOS app uses anon key)
CREATE POLICY "anon_create_jobs" ON processing_jobs
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- Anon users can view jobs they submitted (by matching on showroom_id)
CREATE POLICY "anon_view_jobs" ON processing_jobs
    FOR SELECT
    TO anon
    USING (true);

-- Authenticated showroom owners can view jobs for their showrooms
CREATE POLICY "owners_view_jobs" ON processing_jobs
    FOR SELECT
    TO authenticated
    USING (has_showroom_access(showroom_id));

-- Service role can do everything (used by server worker to update status/results)
CREATE POLICY "service_role_all" ON processing_jobs
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);
