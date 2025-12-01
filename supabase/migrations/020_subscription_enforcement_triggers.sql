-- ============================================
-- NEXTLEAN SCAN - SUBSCRIPTION ENFORCEMENT TRIGGERS
-- Migration: 020_subscription_enforcement_triggers
-- Purpose: Enforce limits at database level with triggers
-- ============================================

-- ============================================
-- TRIGGER: Check Product Insert Limit
-- Prevents adding products beyond plan limit
-- ============================================
CREATE OR REPLACE FUNCTION check_product_insert_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_result JSONB;
    v_access JSONB;
BEGIN
    -- First check subscription access
    v_access := check_subscription_access(NEW.showroom_id);

    IF NOT (v_access->>'has_access')::BOOLEAN THEN
        RAISE EXCEPTION 'Subscription issue: %. Please update your subscription.',
            v_access->>'reason';
    END IF;

    -- Then check product limit
    v_result := check_limit(NEW.showroom_id, 'products');

    IF NOT (v_result->>'allowed')::BOOLEAN THEN
        RAISE EXCEPTION 'Product limit reached (% of %). Please upgrade your plan to add more products.',
            v_result->>'current',
            v_result->>'limit';
    END IF;

    -- Log if approaching limit (soft warning)
    IF (v_result->>'warning')::BOOLEAN THEN
        PERFORM log_feature_access(
            NEW.showroom_id,
            'product_add_warning',
            true,
            NULL,
            NULL,
            NULL,
            jsonb_build_object('percentage', v_result->>'percentage')
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_check_product_insert_limit ON products;
CREATE TRIGGER trigger_check_product_insert_limit
    BEFORE INSERT ON products
    FOR EACH ROW
    EXECUTE FUNCTION check_product_insert_limit();

-- ============================================
-- TRIGGER: Check Team Member Insert Limit
-- Prevents adding team members beyond plan limit
-- ============================================
CREATE OR REPLACE FUNCTION check_team_member_insert_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_result JSONB;
    v_access JSONB;
BEGIN
    -- First check subscription access
    v_access := check_subscription_access(NEW.showroom_id);

    IF NOT (v_access->>'has_access')::BOOLEAN THEN
        RAISE EXCEPTION 'Subscription issue: %. Please update your subscription.',
            v_access->>'reason';
    END IF;

    -- Then check team member limit
    v_result := check_limit(NEW.showroom_id, 'team_members');

    IF NOT (v_result->>'allowed')::BOOLEAN THEN
        RAISE EXCEPTION 'Team member limit reached (% of %). Please upgrade your plan to add more team members.',
            v_result->>'current',
            v_result->>'limit';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_check_team_member_insert_limit ON showroom_users;
CREATE TRIGGER trigger_check_team_member_insert_limit
    BEFORE INSERT ON showroom_users
    FOR EACH ROW
    EXECUTE FUNCTION check_team_member_insert_limit();

-- ============================================
-- TRIGGER: Check Project Insert Limit
-- Enhanced version that checks both access and limits
-- ============================================
CREATE OR REPLACE FUNCTION check_project_insert_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_limit_result JSONB;
    v_access_result JSONB;
BEGIN
    -- Check subscription access first
    v_access_result := check_subscription_access(NEW.showroom_id);

    IF NOT (v_access_result->>'has_access')::BOOLEAN THEN
        -- Log the denial
        PERFORM log_feature_access(
            NEW.showroom_id,
            'project_submission',
            false,
            v_access_result->>'reason',
            NULL,
            NULL,
            v_access_result
        );

        RAISE EXCEPTION 'Subscription issue: %. Please update your subscription.',
            v_access_result->>'reason';
    END IF;

    -- Check project limit
    v_limit_result := check_limit(NEW.showroom_id, 'projects');

    IF NOT (v_limit_result->>'allowed')::BOOLEAN THEN
        -- Log the denial
        PERFORM log_feature_access(
            NEW.showroom_id,
            'project_submission',
            false,
            'project_limit_reached',
            NULL,
            NULL,
            v_limit_result
        );

        RAISE EXCEPTION 'Project limit reached (% of %). Please upgrade your plan to submit more projects.',
            v_limit_result->>'current',
            v_limit_result->>'limit';
    END IF;

    -- Log successful submission
    PERFORM log_feature_access(
        NEW.showroom_id,
        'project_submission',
        true,
        NULL,
        NULL,
        NULL,
        jsonb_build_object(
            'current', v_limit_result->>'current',
            'limit', v_limit_result->>'limit'
        )
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Replace existing project trigger
DROP TRIGGER IF EXISTS trigger_check_project_insert ON projects;
DROP TRIGGER IF EXISTS trigger_check_project_insert_limit ON projects;
CREATE TRIGGER trigger_check_project_insert_limit
    BEFORE INSERT ON projects
    FOR EACH ROW
    EXECUTE FUNCTION check_project_insert_limit();

-- ============================================
-- FUNCTION: Validate Feature Access
-- Used by Edge Functions to check feature availability
-- ============================================
CREATE OR REPLACE FUNCTION validate_feature_access(
    p_showroom_id UUID,
    p_feature_name TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_access JSONB;
    v_has_feature BOOLEAN;
    v_result JSONB;
BEGIN
    -- Check subscription access
    v_access := check_subscription_access(p_showroom_id);

    IF NOT (v_access->>'has_access')::BOOLEAN THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', v_access->>'reason',
            'subscription_status', v_access->>'status'
        );
    END IF;

    -- Check specific feature
    v_has_feature := check_plan_feature(p_showroom_id, p_feature_name);

    IF NOT v_has_feature THEN
        -- Determine which plan is needed
        v_result := jsonb_build_object(
            'allowed', false,
            'reason', 'feature_not_available',
            'feature', p_feature_name,
            'current_plan', v_access->>'plan',
            'upgrade_required', CASE p_feature_name
                WHEN 'webhook_access' THEN 'pro'
                WHEN 'api_access' THEN 'pro'
                WHEN 'autocad_export' THEN 'pro'
                WHEN 'priority_support' THEN 'pro'
                WHEN 'crm_integration' THEN 'enterprise'
                WHEN 'ai_agent' THEN 'enterprise'
                ELSE 'pro'
            END
        );

        -- Log the access attempt
        PERFORM log_feature_access(
            p_showroom_id,
            p_feature_name,
            false,
            'feature_not_available',
            NULL,
            NULL,
            v_result
        );

        RETURN v_result;
    END IF;

    -- Feature is available
    RETURN jsonb_build_object(
        'allowed', true,
        'feature', p_feature_name,
        'plan', v_access->>'plan'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Reset Period Counters
-- Called periodically to reset usage for new billing period
-- ============================================
CREATE OR REPLACE FUNCTION reset_period_counters()
RETURNS TABLE(showroom_id UUID, old_count INT) AS $$
BEGIN
    RETURN QUERY
    UPDATE showrooms s
    SET
        project_count_this_period = 0,
        period_start_date = CURRENT_DATE
    WHERE
        s.subscription_status = 'active'
        AND s.current_period_end IS NOT NULL
        AND s.current_period_end < NOW()
        AND (s.period_start_date IS NULL OR s.period_start_date < CURRENT_DATE - INTERVAL '30 days')
    RETURNING s.id, s.project_count_this_period;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Set Grace Period
-- Sets grace period for a showroom (used when payment fails or trial ends)
-- ============================================
CREATE OR REPLACE FUNCTION set_grace_period(
    p_showroom_id UUID,
    p_days INT DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    v_plan subscription_plans;
    v_grace_days INT;
BEGIN
    -- Get plan to find default grace period
    SELECT sp.* INTO v_plan
    FROM showrooms s
    JOIN subscription_plans sp ON s.subscription_plan_id = sp.id
    WHERE s.id = p_showroom_id;

    v_grace_days := COALESCE(p_days, v_plan.grace_period_days, 3);

    UPDATE showrooms
    SET grace_period_ends_at = NOW() + (v_grace_days || ' days')::INTERVAL
    WHERE id = p_showroom_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Expire Trial
-- Called when trial ends, sets grace period
-- ============================================
CREATE OR REPLACE FUNCTION expire_trial(p_showroom_id UUID)
RETURNS void AS $$
BEGIN
    -- Set grace period
    PERFORM set_grace_period(p_showroom_id);

    -- Record in subscription history
    INSERT INTO subscription_history (
        showroom_id,
        event_type,
        details
    ) VALUES (
        p_showroom_id,
        'trial_expired',
        jsonb_build_object(
            'trial_ends_at', (SELECT trial_ends_at FROM showrooms WHERE id = p_showroom_id),
            'grace_period_ends_at', (SELECT grace_period_ends_at FROM showrooms WHERE id = p_showroom_id)
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
