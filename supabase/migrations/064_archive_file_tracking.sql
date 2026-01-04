-- ============================================
-- NEXTLEAN SCAN - ARCHIVE FILE TRACKING
-- Migration: 064_archive_file_tracking
-- Purpose: Track individual archived files and restore operations
-- ============================================

-- Track individual files for each archived project
CREATE TABLE IF NOT EXISTS project_archived_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Original Supabase Storage location
    original_bucket TEXT NOT NULL DEFAULT 'scans',
    original_path TEXT NOT NULL,

    -- S3 Glacier location
    s3_bucket TEXT NOT NULL,
    s3_key TEXT NOT NULL,

    -- File metadata
    file_type TEXT NOT NULL, -- 'usdz', 'preview', 'video', 'video_thumbnail', 'visualization_photo'
    file_size_bytes BIGINT,
    content_type TEXT,

    -- Status tracking
    archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    restore_status TEXT DEFAULT 'archived' CHECK (restore_status IN ('archived', 'restoring', 'restored')),
    restore_completed_at TIMESTAMPTZ,

    -- S3 restore metadata
    s3_restore_request_id TEXT,
    s3_restore_tier TEXT, -- 'Expedited', 'Standard', 'Bulk'

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_project_archived_files_project ON project_archived_files(project_id);
CREATE INDEX IF NOT EXISTS idx_project_archived_files_status ON project_archived_files(restore_status)
    WHERE restore_status = 'restoring';

-- Track restore requests for auditing
CREATE TABLE IF NOT EXISTS restore_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Who requested
    requested_by UUID REFERENCES auth.users(id),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    -- Status
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'expired')),

    -- Timing
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ, -- When restored files will be re-archived

    -- Notification
    notification_emails TEXT, -- Comma-separated list
    notification_sent_at TIMESTAMPTZ,

    -- Error tracking
    error_message TEXT,
    retry_count INT DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_restore_requests_project ON restore_requests(project_id);
CREATE INDEX IF NOT EXISTS idx_restore_requests_status ON restore_requests(status) WHERE status IN ('pending', 'processing');
CREATE INDEX IF NOT EXISTS idx_restore_requests_expires ON restore_requests(expires_at) WHERE status = 'completed';

-- Function to get archive stats for a showroom
CREATE OR REPLACE FUNCTION get_showroom_archive_stats(p_showroom_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_stats JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_projects', COUNT(*),
        'hot_projects', COUNT(*) FILTER (WHERE storage_tier = 'hot'),
        'archived_projects', COUNT(*) FILTER (WHERE storage_tier = 'archived'),
        'restoring_projects', COUNT(*) FILTER (WHERE storage_tier = 'restoring'),
        'total_archived_size_bytes', (
            SELECT COALESCE(SUM(paf.file_size_bytes), 0)
            FROM project_archived_files paf
            JOIN projects p ON p.id = paf.project_id
            WHERE p.showroom_id = p_showroom_id
        )
    ) INTO v_stats
    FROM projects
    WHERE showroom_id = p_showroom_id;

    RETURN v_stats;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS policies for project_archived_files
ALTER TABLE project_archived_files ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view archived files for their showroom projects"
ON project_archived_files FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM projects p
        JOIN showroom_users su ON su.showroom_id = p.showroom_id
        WHERE p.id = project_archived_files.project_id
        AND su.user_id = auth.uid()
        AND su.is_active = true
    )
    OR is_super_admin()
);

-- RLS policies for restore_requests
ALTER TABLE restore_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view restore requests for their showroom"
ON restore_requests FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM showroom_users su
        WHERE su.showroom_id = restore_requests.showroom_id
        AND su.user_id = auth.uid()
        AND su.is_active = true
    )
    OR is_super_admin()
);

CREATE POLICY "Users can create restore requests for their showroom"
ON restore_requests FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM showroom_users su
        WHERE su.showroom_id = restore_requests.showroom_id
        AND su.user_id = auth.uid()
        AND su.is_active = true
    )
    OR is_super_admin()
);
