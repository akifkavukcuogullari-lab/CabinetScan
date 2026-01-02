-- ============================================
-- NEXTLEAN SCAN - STORAGE TIER ARCHIVAL SYSTEM
-- Migration: 063_storage_tier_archival
-- Purpose: Add storage tier tracking for automatic file archival after 60 days
-- ============================================

-- Add storage tier columns to projects table
ALTER TABLE projects
ADD COLUMN IF NOT EXISTS storage_tier TEXT DEFAULT 'hot' CHECK (storage_tier IN ('hot', 'archived', 'restoring')),
ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS restore_requested_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS restore_available_until TIMESTAMPTZ;

-- Create index for efficient queries on storage tier
CREATE INDEX IF NOT EXISTS idx_projects_storage_tier ON projects(storage_tier);
CREATE INDEX IF NOT EXISTS idx_projects_archived_at ON projects(archived_at) WHERE archived_at IS NOT NULL;

-- Function to archive old project files (called by pg_cron)
CREATE OR REPLACE FUNCTION archive_old_project_files()
RETURNS INTEGER AS $$
DECLARE
  archived_count INTEGER := 0;
BEGIN
  -- Mark projects older than 60 days as archived
  -- Only archive projects that have files (scan_file_url, preview_image_url, or video_url)
  UPDATE projects
  SET
    storage_tier = 'archived',
    archived_at = NOW()
  WHERE
    storage_tier = 'hot'
    AND created_at < NOW() - INTERVAL '60 days'
    AND (scan_file_url IS NOT NULL OR preview_image_url IS NOT NULL);

  GET DIAGNOSTICS archived_count = ROW_COUNT;

  -- Log the archival action
  RAISE NOTICE 'Archived % projects older than 60 days', archived_count;

  RETURN archived_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to mark project as restoring (called from Edge Function)
CREATE OR REPLACE FUNCTION request_project_restore(project_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE projects
  SET
    storage_tier = 'restoring',
    restore_requested_at = NOW()
  WHERE
    id = project_uuid
    AND storage_tier = 'archived';

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to mark project as restored (called after Glacier restore completes)
CREATE OR REPLACE FUNCTION complete_project_restore(project_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE projects
  SET
    storage_tier = 'hot',
    restore_available_until = NOW() + INTERVAL '48 hours',
    archived_at = NULL,
    restore_requested_at = NULL
  WHERE
    id = project_uuid
    AND storage_tier = 'restoring';

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to re-archive expired restores (called by pg_cron)
CREATE OR REPLACE FUNCTION rearchive_expired_restores()
RETURNS INTEGER AS $$
DECLARE
  rearchived_count INTEGER := 0;
BEGIN
  -- Re-archive projects where restore window has expired
  UPDATE projects
  SET
    storage_tier = 'archived',
    archived_at = NOW(),
    restore_available_until = NULL
  WHERE
    storage_tier = 'hot'
    AND restore_available_until IS NOT NULL
    AND restore_available_until < NOW();

  GET DIAGNOSTICS rearchived_count = ROW_COUNT;

  RETURN rearchived_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Enable pg_cron extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule daily archival job at 2 AM UTC
SELECT cron.schedule(
  'archive-old-projects',
  '0 2 * * *',  -- Every day at 2 AM UTC
  $$SELECT archive_old_project_files()$$
);

-- Schedule hourly check for expired restores
SELECT cron.schedule(
  'rearchive-expired-restores',
  '0 * * * *',  -- Every hour
  $$SELECT rearchive_expired_restores()$$
);

-- Add comment for documentation
COMMENT ON COLUMN projects.storage_tier IS 'Storage tier: hot (immediate access), archived (cold storage), restoring (restore in progress)';
COMMENT ON COLUMN projects.archived_at IS 'Timestamp when project files were moved to cold storage';
COMMENT ON COLUMN projects.restore_requested_at IS 'Timestamp when restore was requested';
COMMENT ON COLUMN projects.restore_available_until IS 'Timestamp until which restored files are available for download';
