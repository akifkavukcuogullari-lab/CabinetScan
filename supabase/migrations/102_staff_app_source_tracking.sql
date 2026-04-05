-- ============================================
-- STAFF APP SOURCE TRACKING
-- Migration: 102_staff_app_source_tracking
-- Purpose: Track where projects originate from (ios_customer, ios_staff, dashboard)
--          and which staff member created them
-- ============================================

-- Add source column to track project origin
ALTER TABLE projects
ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'ios_customer';

-- Add created_by_user_id to track which staff member created the project
ALTER TABLE projects
ADD COLUMN IF NOT EXISTS created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- Index for filtering projects by source within a showroom
CREATE INDEX IF NOT EXISTS idx_projects_showroom_source ON projects(showroom_id, source);

-- Partial index on created_by_user_id (only index rows where it's set)
CREATE INDEX IF NOT EXISTS idx_projects_created_by_user ON projects(created_by_user_id)
    WHERE created_by_user_id IS NOT NULL;

-- Documentation
COMMENT ON COLUMN projects.source IS 'Where the project was created from: ios_customer, ios_staff, or dashboard';
COMMENT ON COLUMN projects.created_by_user_id IS 'The auth.users ID of the staff member who created this project (NULL for customer-created projects)';
