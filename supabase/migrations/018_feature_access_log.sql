-- ============================================
-- NEXTLEAN SCAN - FEATURE ACCESS LOGGING
-- Migration: 018_feature_access_log
-- Purpose: Log feature access attempts for analytics and debugging
-- ============================================

-- Create feature access log table
CREATE TABLE IF NOT EXISTS feature_access_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    -- What was accessed
    feature_name TEXT NOT NULL,
    was_allowed BOOLEAN NOT NULL,
    denial_reason TEXT,

    -- Context
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    request_path TEXT,
    metadata JSONB DEFAULT '{}',

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add comments
COMMENT ON TABLE feature_access_log IS 'Logs all feature access attempts for analytics';
COMMENT ON COLUMN feature_access_log.feature_name IS 'Name of the feature accessed (e.g., webhook_access, project_submission)';
COMMENT ON COLUMN feature_access_log.was_allowed IS 'Whether the access was allowed';
COMMENT ON COLUMN feature_access_log.denial_reason IS 'Reason for denial: limit_reached, feature_not_available, subscription_expired, etc.';

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_feature_access_log_showroom
ON feature_access_log(showroom_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_feature_access_log_feature
ON feature_access_log(feature_name, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_feature_access_log_denied
ON feature_access_log(showroom_id, was_allowed, created_at DESC)
WHERE was_allowed = false;

-- Enable RLS
ALTER TABLE feature_access_log ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Showroom users can view their feature access logs"
    ON feature_access_log FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY "System can insert feature access logs"
    ON feature_access_log FOR INSERT
    WITH CHECK (true);

CREATE POLICY "Super admins can manage all feature access logs"
    ON feature_access_log FOR ALL
    USING (is_super_admin());

-- Function to log feature access
CREATE OR REPLACE FUNCTION log_feature_access(
    p_showroom_id UUID,
    p_feature_name TEXT,
    p_was_allowed BOOLEAN,
    p_denial_reason TEXT DEFAULT NULL,
    p_user_id UUID DEFAULT NULL,
    p_request_path TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
)
RETURNS UUID AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO feature_access_log (
        showroom_id,
        feature_name,
        was_allowed,
        denial_reason,
        user_id,
        request_path,
        metadata
    ) VALUES (
        p_showroom_id,
        p_feature_name,
        p_was_allowed,
        p_denial_reason,
        p_user_id,
        p_request_path,
        p_metadata
    )
    RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to clean up old logs (keep 90 days)
CREATE OR REPLACE FUNCTION cleanup_old_feature_logs()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM feature_access_log
    WHERE created_at < NOW() - INTERVAL '90 days';

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get feature access statistics
CREATE OR REPLACE FUNCTION get_feature_access_stats(
    p_showroom_id UUID,
    p_days INT DEFAULT 30
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_attempts', COUNT(*),
        'allowed', COUNT(*) FILTER (WHERE was_allowed = true),
        'denied', COUNT(*) FILTER (WHERE was_allowed = false),
        'by_feature', (
            SELECT jsonb_object_agg(
                feature_name,
                jsonb_build_object(
                    'allowed', allowed_count,
                    'denied', denied_count
                )
            )
            FROM (
                SELECT
                    feature_name,
                    COUNT(*) FILTER (WHERE was_allowed = true) as allowed_count,
                    COUNT(*) FILTER (WHERE was_allowed = false) as denied_count
                FROM feature_access_log
                WHERE showroom_id = p_showroom_id
                AND created_at >= NOW() - (p_days || ' days')::INTERVAL
                GROUP BY feature_name
            ) sub
        ),
        'denial_reasons', (
            SELECT jsonb_object_agg(denial_reason, reason_count)
            FROM (
                SELECT denial_reason, COUNT(*) as reason_count
                FROM feature_access_log
                WHERE showroom_id = p_showroom_id
                AND created_at >= NOW() - (p_days || ' days')::INTERVAL
                AND was_allowed = false
                AND denial_reason IS NOT NULL
                GROUP BY denial_reason
            ) sub
        )
    ) INTO v_result
    FROM feature_access_log
    WHERE showroom_id = p_showroom_id
    AND created_at >= NOW() - (p_days || ' days')::INTERVAL;

    RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
