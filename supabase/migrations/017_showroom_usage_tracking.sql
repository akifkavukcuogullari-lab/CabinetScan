-- ============================================
-- NEXTLEAN SCAN - SHOWROOM USAGE TRACKING
-- Migration: 017_showroom_usage_tracking
-- Purpose: Add comprehensive usage tracking to showrooms
-- ============================================

-- Add usage tracking columns to showrooms
ALTER TABLE showrooms
ADD COLUMN IF NOT EXISTS product_count INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS storage_used_bytes BIGINT DEFAULT 0,
ADD COLUMN IF NOT EXISTS team_member_count INT DEFAULT 1,
ADD COLUMN IF NOT EXISTS period_start_date DATE,
ADD COLUMN IF NOT EXISTS grace_period_ends_at TIMESTAMPTZ;

-- Add comments
COMMENT ON COLUMN showrooms.product_count IS 'Current number of active products';
COMMENT ON COLUMN showrooms.storage_used_bytes IS 'Total storage used in bytes';
COMMENT ON COLUMN showrooms.team_member_count IS 'Current number of team members';
COMMENT ON COLUMN showrooms.period_start_date IS 'Start of current billing period for usage tracking';
COMMENT ON COLUMN showrooms.grace_period_ends_at IS 'When grace period expires (for trial/payment issues)';

-- Initialize product_count from existing data
UPDATE showrooms s
SET product_count = (
    SELECT COUNT(*)
    FROM products p
    WHERE p.showroom_id = s.id AND p.is_active = true
);

-- Initialize team_member_count from existing data
UPDATE showrooms s
SET team_member_count = (
    SELECT COUNT(*)
    FROM showroom_users su
    WHERE su.showroom_id = s.id AND su.is_active = true
);

-- Create usage snapshots table for historical tracking
CREATE TABLE IF NOT EXISTS usage_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    -- Snapshot date
    snapshot_date DATE NOT NULL,

    -- Usage metrics at time of snapshot
    project_count INT NOT NULL DEFAULT 0,
    product_count INT NOT NULL DEFAULT 0,
    storage_bytes BIGINT NOT NULL DEFAULT 0,
    team_member_count INT NOT NULL DEFAULT 0,

    -- Plan limits at time of snapshot (for historical comparison)
    project_limit INT,
    product_limit INT,
    storage_limit_gb INT,
    team_member_limit INT,

    -- Subscription info
    plan_slug TEXT,
    subscription_status TEXT,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT usage_snapshots_unique UNIQUE (showroom_id, snapshot_date)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_usage_snapshots_showroom_date
ON usage_snapshots(showroom_id, snapshot_date DESC);

-- Enable RLS
ALTER TABLE usage_snapshots ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Showroom users can view their usage snapshots"
    ON usage_snapshots FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY "Super admins can manage all usage snapshots"
    ON usage_snapshots FOR ALL
    USING (is_super_admin());

-- Function to create daily usage snapshot
CREATE OR REPLACE FUNCTION create_usage_snapshot(p_showroom_id UUID)
RETURNS void AS $$
DECLARE
    v_showroom showrooms;
    v_plan subscription_plans;
BEGIN
    SELECT * INTO v_showroom FROM showrooms WHERE id = p_showroom_id;

    IF v_showroom.subscription_plan_id IS NOT NULL THEN
        SELECT * INTO v_plan FROM subscription_plans WHERE id = v_showroom.subscription_plan_id;
    END IF;

    INSERT INTO usage_snapshots (
        showroom_id,
        snapshot_date,
        project_count,
        product_count,
        storage_bytes,
        team_member_count,
        project_limit,
        product_limit,
        storage_limit_gb,
        team_member_limit,
        plan_slug,
        subscription_status
    ) VALUES (
        p_showroom_id,
        CURRENT_DATE,
        COALESCE(v_showroom.project_count_this_period, 0),
        COALESCE(v_showroom.product_count, 0),
        COALESCE(v_showroom.storage_used_bytes, 0),
        COALESCE(v_showroom.team_member_count, 1),
        v_plan.project_limit,
        v_plan.product_limit,
        v_plan.storage_limit_gb,
        v_plan.team_member_limit,
        v_showroom.subscription_plan,
        v_showroom.subscription_status::TEXT
    )
    ON CONFLICT (showroom_id, snapshot_date)
    DO UPDATE SET
        project_count = EXCLUDED.project_count,
        product_count = EXCLUDED.product_count,
        storage_bytes = EXCLUDED.storage_bytes,
        team_member_count = EXCLUDED.team_member_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
