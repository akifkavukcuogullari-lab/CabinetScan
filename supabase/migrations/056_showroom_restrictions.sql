-- ============================================
-- NEXTLEAN SCAN - SHOWROOM RESTRICTIONS
-- Migration: 056_showroom_restrictions
-- Purpose: Remove iOS restrictions, add showroom-side restrictions
-- ============================================

-- ============================================
-- REMOVE PROJECT LIMIT TRIGGER
-- iOS app should always be able to submit projects
-- Showroom owners will be restricted from VIEWING projects instead
-- ============================================

-- Drop the trigger that blocks project inserts
DROP TRIGGER IF EXISTS trigger_check_project_insert_limit ON projects;
DROP TRIGGER IF EXISTS trigger_check_project_insert ON projects;

-- Keep the increment trigger (we still want to count projects)
-- trigger_increment_project_count remains active

-- ============================================
-- STORAGE ENFORCEMENT
-- Block file uploads when storage limit exceeded
-- ============================================

-- Function to check storage limit before upload
CREATE OR REPLACE FUNCTION check_storage_limit(p_showroom_id UUID, p_file_size_bytes BIGINT)
RETURNS JSONB AS $$
DECLARE
    v_current_bytes BIGINT;
    v_limit_gb NUMERIC;
    v_limit_bytes BIGINT;
    v_new_total BIGINT;
BEGIN
    -- Get current storage used
    SELECT COALESCE(storage_used_bytes, 0) INTO v_current_bytes
    FROM showrooms
    WHERE id = p_showroom_id;

    -- Get storage limit from plan
    SELECT sp.storage_limit_gb INTO v_limit_gb
    FROM showrooms s
    JOIN subscription_plans sp ON s.subscription_plan_id = sp.id
    WHERE s.id = p_showroom_id;

    -- NULL means unlimited
    IF v_limit_gb IS NULL THEN
        RETURN jsonb_build_object(
            'allowed', true,
            'unlimited', true
        );
    END IF;

    -- Convert GB to bytes
    v_limit_bytes := (v_limit_gb * 1024 * 1024 * 1024)::BIGINT;
    v_new_total := v_current_bytes + p_file_size_bytes;

    IF v_new_total > v_limit_bytes THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'storage_limit_exceeded',
            'current_bytes', v_current_bytes,
            'limit_bytes', v_limit_bytes,
            'limit_gb', v_limit_gb,
            'file_size_bytes', p_file_size_bytes
        );
    END IF;

    RETURN jsonb_build_object(
        'allowed', true,
        'current_bytes', v_current_bytes,
        'limit_bytes', v_limit_bytes,
        'remaining_bytes', v_limit_bytes - v_current_bytes
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to update storage used after upload
CREATE OR REPLACE FUNCTION update_storage_used(p_showroom_id UUID, p_bytes_delta BIGINT)
RETURNS void AS $$
BEGIN
    UPDATE showrooms
    SET storage_used_bytes = GREATEST(0, COALESCE(storage_used_bytes, 0) + p_bytes_delta)
    WHERE id = p_showroom_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PROJECT ACCESS CHECK
-- Used by dashboard to check if showroom can view projects
-- ============================================

CREATE OR REPLACE FUNCTION check_project_access(p_showroom_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_current INT;
    v_limit INT;
    v_status TEXT;
    v_plan TEXT;
BEGIN
    -- Get showroom info
    SELECT
        COALESCE(s.project_count_this_period, 0),
        sp.project_limit,
        s.subscription_status,
        s.subscription_plan
    INTO v_current, v_limit, v_status, v_plan
    FROM showrooms s
    LEFT JOIN subscription_plans sp ON s.subscription_plan_id = sp.id
    WHERE s.id = p_showroom_id;

    -- Check subscription status
    IF v_status NOT IN ('trial', 'active') THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'subscription_inactive',
            'status', v_status
        );
    END IF;

    -- NULL limit means unlimited
    IF v_limit IS NULL THEN
        RETURN jsonb_build_object(
            'allowed', true,
            'unlimited', true,
            'current', v_current
        );
    END IF;

    -- Check if over limit
    IF v_current > v_limit THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'project_limit_exceeded',
            'current', v_current,
            'limit', v_limit,
            'overage', v_current - v_limit,
            'message', 'You have exceeded your monthly project limit. Please upgrade your plan to view all projects.'
        );
    END IF;

    RETURN jsonb_build_object(
        'allowed', true,
        'current', v_current,
        'limit', v_limit,
        'remaining', v_limit - v_current
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PRODUCT LIMIT - Keep existing trigger
-- Showroom owners still can't add products over limit
-- ============================================

-- Product trigger remains active (from migration 020)

-- ============================================
-- GRANT PERMISSIONS
-- ============================================

GRANT EXECUTE ON FUNCTION check_storage_limit(UUID, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION check_storage_limit(UUID, BIGINT) TO anon;
GRANT EXECUTE ON FUNCTION check_storage_limit(UUID, BIGINT) TO service_role;

GRANT EXECUTE ON FUNCTION update_storage_used(UUID, BIGINT) TO service_role;

GRANT EXECUTE ON FUNCTION check_project_access(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION check_project_access(UUID) TO service_role;

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON FUNCTION check_storage_limit(UUID, BIGINT) IS 'Check if showroom can upload file of given size. Returns allowed:true/false with details.';
COMMENT ON FUNCTION update_storage_used(UUID, BIGINT) IS 'Update storage_used_bytes for showroom after upload/delete. Use negative value for deletions.';
COMMENT ON FUNCTION check_project_access(UUID) IS 'Check if showroom can view projects. Returns allowed:false if over limit.';
