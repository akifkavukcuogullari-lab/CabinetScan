-- ============================================
-- NEXTLEAN SCAN - VIDEO CAPTURE SUPPORT
-- Migration: 021_video_capture_support
-- Purpose: Add video capture capability for PRO+ subscriptions
-- ============================================

-- ============================================
-- 1. ADD VIDEO COLUMNS TO PROJECT_MEASUREMENTS
-- ============================================

ALTER TABLE project_measurements
ADD COLUMN IF NOT EXISTS video_url TEXT,
ADD COLUMN IF NOT EXISTS video_thumbnail_url TEXT,
ADD COLUMN IF NOT EXISTS video_duration_seconds INT,
ADD COLUMN IF NOT EXISTS video_size_bytes BIGINT,
ADD COLUMN IF NOT EXISTS video_resolution TEXT,
ADD COLUMN IF NOT EXISTS video_format TEXT DEFAULT 'mp4',
ADD COLUMN IF NOT EXISTS video_uploaded_at TIMESTAMPTZ;

-- Comments for documentation
COMMENT ON COLUMN project_measurements.video_url IS 'URL to the scan video in storage bucket';
COMMENT ON COLUMN project_measurements.video_thumbnail_url IS 'URL to video thumbnail/poster image';
COMMENT ON COLUMN project_measurements.video_duration_seconds IS 'Video duration in seconds';
COMMENT ON COLUMN project_measurements.video_size_bytes IS 'Video file size in bytes';
COMMENT ON COLUMN project_measurements.video_resolution IS 'Video resolution, e.g., 1920x1080';
COMMENT ON COLUMN project_measurements.video_format IS 'Video container format (mp4, mov)';
COMMENT ON COLUMN project_measurements.video_uploaded_at IS 'Timestamp when video was uploaded';

-- ============================================
-- 2. ADD VIDEO FEATURE FLAGS TO SUBSCRIPTION_PLANS
-- ============================================

ALTER TABLE subscription_plans
ADD COLUMN IF NOT EXISTS has_video_capture BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS video_max_duration_seconds INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS video_max_size_mb INT DEFAULT 0;

-- Update existing plans with video settings
-- Trial: Video enabled (same as Pro during trial)
UPDATE subscription_plans SET
    has_video_capture = true,
    video_max_duration_seconds = 300,
    video_max_size_mb = 500
WHERE slug = 'trial';

-- Basic: No video capture
UPDATE subscription_plans SET
    has_video_capture = false,
    video_max_duration_seconds = 0,
    video_max_size_mb = 0
WHERE slug = 'basic';

-- Pro: Full video capture
UPDATE subscription_plans SET
    has_video_capture = true,
    video_max_duration_seconds = 300,
    video_max_size_mb = 500
WHERE slug = 'pro';

-- Enterprise: Extended video capture
UPDATE subscription_plans SET
    has_video_capture = true,
    video_max_duration_seconds = 600,
    video_max_size_mb = 1000
WHERE slug = 'enterprise';

-- ============================================
-- 3. UPDATE SCANS BUCKET TO SUPPORT VIDEO
-- ============================================

-- Update scans bucket to allow video mime types and increase size limit
UPDATE storage.buckets
SET
    allowed_mime_types = ARRAY[
        'model/vnd.usdz+zip',
        'model/gltf-binary',
        'application/octet-stream',
        'image/png',
        'image/jpeg',
        'application/json',
        'video/mp4',
        'video/quicktime'
    ],
    file_size_limit = 524288000  -- 500MB for videos
WHERE id = 'scans';

-- ============================================
-- 4. HELPER FUNCTION: Check Video Capture Permission
-- ============================================

CREATE OR REPLACE FUNCTION check_video_capture_permission(p_showroom_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_plan subscription_plans;
    v_showroom showrooms;
BEGIN
    -- Get showroom and plan
    SELECT s.* INTO v_showroom
    FROM showrooms s
    WHERE s.id = p_showroom_id;

    IF v_showroom.id IS NULL THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'showroom_not_found'
        );
    END IF;

    SELECT sp.* INTO v_plan
    FROM subscription_plans sp
    WHERE sp.id = v_showroom.subscription_plan_id;

    -- Check if video capture is enabled
    IF NOT COALESCE(v_plan.has_video_capture, false) THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'feature_not_available',
            'message', 'Video capture is available on Pro and Enterprise plans'
        );
    END IF;

    -- Check subscription status
    IF v_showroom.subscription_status NOT IN ('trial', 'active') THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'subscription_inactive',
            'message', 'Active subscription required for video capture'
        );
    END IF;

    -- Return allowed with limits
    RETURN jsonb_build_object(
        'allowed', true,
        'max_duration_seconds', v_plan.video_max_duration_seconds,
        'max_size_mb', v_plan.video_max_size_mb
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 5. UPDATE CHECK_PLAN_FEATURE FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION check_plan_feature(p_showroom_id UUID, p_feature TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_plan subscription_plans;
BEGIN
    SELECT sp.* INTO v_plan
    FROM showrooms s
    JOIN subscription_plans sp ON s.subscription_plan_id = sp.id
    WHERE s.id = p_showroom_id;

    IF v_plan.id IS NULL THEN
        RETURN false;
    END IF;

    CASE p_feature
        WHEN 'webhook_access' THEN RETURN v_plan.has_webhook_access;
        WHEN 'api_access' THEN RETURN v_plan.has_api_access;
        WHEN 'autocad_export' THEN RETURN v_plan.has_autocad_export;
        WHEN 'priority_support' THEN RETURN v_plan.has_priority_support;
        WHEN 'crm_integration' THEN RETURN v_plan.has_crm_integration;
        WHEN 'ai_agent' THEN RETURN v_plan.has_ai_agent;
        WHEN 'custom_branding' THEN RETURN v_plan.has_custom_branding;
        WHEN 'video_capture' THEN RETURN v_plan.has_video_capture;
        ELSE RETURN false;
    END CASE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
