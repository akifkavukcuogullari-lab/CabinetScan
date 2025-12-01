-- ============================================
-- NEXTLEAN SCAN - ENHANCED LIMIT FUNCTIONS
-- Migration: 019_enhanced_limit_functions
-- Purpose: Comprehensive limit checking and subscription access functions
-- ============================================

-- ============================================
-- FUNCTION: Check Any Limit
-- Returns detailed info about a specific limit type
-- ============================================
CREATE OR REPLACE FUNCTION check_limit(
    p_showroom_id UUID,
    p_limit_type TEXT -- 'projects', 'products', 'storage', 'team_members'
)
RETURNS JSONB AS $$
DECLARE
    v_plan subscription_plans;
    v_showroom showrooms;
    v_limit BIGINT;
    v_current BIGINT;
    v_soft_threshold DECIMAL;
    v_percentage DECIMAL;
BEGIN
    -- Get showroom
    SELECT * INTO v_showroom
    FROM showrooms
    WHERE id = p_showroom_id;

    IF v_showroom.id IS NULL THEN
        RETURN jsonb_build_object('error', 'Showroom not found');
    END IF;

    -- Get plan (might be null for trial without explicit plan)
    SELECT * INTO v_plan
    FROM subscription_plans
    WHERE id = v_showroom.subscription_plan_id;

    -- If no plan, use trial defaults
    IF v_plan.id IS NULL THEN
        SELECT * INTO v_plan
        FROM subscription_plans
        WHERE slug = 'trial';
    END IF;

    -- Get limit and current usage based on type
    CASE p_limit_type
        WHEN 'projects' THEN
            v_limit := v_plan.project_limit;
            v_current := COALESCE(v_showroom.project_count_this_period, 0);
        WHEN 'products' THEN
            v_limit := v_plan.product_limit;
            v_current := COALESCE(v_showroom.product_count, 0);
        WHEN 'storage' THEN
            -- Convert GB to bytes for comparison
            v_limit := CASE
                WHEN v_plan.storage_limit_gb IS NOT NULL
                THEN v_plan.storage_limit_gb::BIGINT * 1024 * 1024 * 1024
                ELSE NULL
            END;
            v_current := COALESCE(v_showroom.storage_used_bytes, 0);
        WHEN 'team_members' THEN
            v_limit := v_plan.team_member_limit;
            v_current := COALESCE(v_showroom.team_member_count, 1);
        ELSE
            RETURN jsonb_build_object('error', 'Invalid limit type. Use: projects, products, storage, team_members');
    END CASE;

    -- NULL limit means unlimited
    IF v_limit IS NULL THEN
        RETURN jsonb_build_object(
            'allowed', true,
            'unlimited', true,
            'current', v_current,
            'limit', null,
            'remaining', null,
            'percentage', 0,
            'warning', false,
            'exceeded', false,
            'limit_type', p_limit_type
        );
    END IF;

    v_soft_threshold := COALESCE(v_plan.soft_limit_threshold, 0.80);
    v_percentage := CASE WHEN v_limit > 0 THEN v_current::DECIMAL / v_limit::DECIMAL ELSE 0 END;

    RETURN jsonb_build_object(
        'allowed', v_current < v_limit,
        'unlimited', false,
        'current', v_current,
        'limit', v_limit,
        'remaining', GREATEST(0, v_limit - v_current),
        'percentage', ROUND(v_percentage * 100, 1),
        'warning', v_percentage >= v_soft_threshold AND v_current < v_limit,
        'exceeded', v_current >= v_limit,
        'limit_type', p_limit_type,
        'soft_threshold', v_soft_threshold * 100
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Check Subscription Access
-- Comprehensive check for whether showroom can use the platform
-- ============================================
CREATE OR REPLACE FUNCTION check_subscription_access(p_showroom_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_showroom showrooms;
    v_plan subscription_plans;
    v_now TIMESTAMPTZ := NOW();
    v_status TEXT;
    v_has_access BOOLEAN;
    v_reason TEXT;
    v_warning TEXT;
BEGIN
    -- Get showroom
    SELECT * INTO v_showroom
    FROM showrooms
    WHERE id = p_showroom_id;

    IF v_showroom.id IS NULL THEN
        RETURN jsonb_build_object(
            'has_access', false,
            'status', 'not_found',
            'reason', 'showroom_not_found'
        );
    END IF;

    -- Get plan
    SELECT * INTO v_plan
    FROM subscription_plans
    WHERE id = v_showroom.subscription_plan_id;

    v_status := v_showroom.subscription_status::TEXT;

    -- Check various conditions
    CASE v_status
        WHEN 'active' THEN
            v_has_access := true;
            v_reason := null;
            -- Check if approaching period end
            IF v_showroom.cancel_at_period_end = true THEN
                v_warning := 'cancellation_pending';
            END IF;

        WHEN 'trial' THEN
            IF v_showroom.trial_ends_at IS NOT NULL AND v_now > v_showroom.trial_ends_at THEN
                -- Trial expired, check grace period
                IF v_showroom.grace_period_ends_at IS NOT NULL AND v_now <= v_showroom.grace_period_ends_at THEN
                    v_has_access := true;
                    v_reason := 'trial_grace_period';
                    v_warning := 'grace_period_active';
                ELSE
                    v_has_access := false;
                    v_reason := 'trial_expired';
                END IF;
            ELSE
                v_has_access := true;
                v_reason := null;
                -- Warn if trial ending soon (3 days)
                IF v_showroom.trial_ends_at IS NOT NULL
                   AND v_showroom.trial_ends_at <= v_now + INTERVAL '3 days' THEN
                    v_warning := 'trial_ending_soon';
                END IF;
            END IF;

        WHEN 'past_due' THEN
            -- Allow access during grace period with warning
            IF v_showroom.grace_period_ends_at IS NOT NULL AND v_now <= v_showroom.grace_period_ends_at THEN
                v_has_access := true;
                v_reason := 'payment_grace_period';
                v_warning := 'payment_overdue';
            ELSE
                v_has_access := false;
                v_reason := 'payment_failed';
            END IF;

        WHEN 'canceled' THEN
            -- Access until period end
            IF v_showroom.current_period_end IS NOT NULL AND v_now <= v_showroom.current_period_end THEN
                v_has_access := true;
                v_reason := 'cancellation_pending';
                v_warning := 'subscription_ending';
            ELSE
                v_has_access := false;
                v_reason := 'subscription_canceled';
            END IF;

        WHEN 'suspended' THEN
            v_has_access := false;
            v_reason := 'subscription_suspended';

        ELSE
            v_has_access := false;
            v_reason := 'unknown_status';
    END CASE;

    RETURN jsonb_build_object(
        'has_access', v_has_access,
        'status', v_status,
        'reason', v_reason,
        'warning', v_warning,
        'plan', v_showroom.subscription_plan,
        'plan_name', v_plan.name,
        'trial_ends_at', v_showroom.trial_ends_at,
        'current_period_end', v_showroom.current_period_end,
        'grace_period_ends_at', v_showroom.grace_period_ends_at,
        'cancel_at_period_end', v_showroom.cancel_at_period_end
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Get All Limits for a Showroom
-- Convenience function to get all limits at once
-- ============================================
CREATE OR REPLACE FUNCTION get_all_limits(p_showroom_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_projects JSONB;
    v_products JSONB;
    v_storage JSONB;
    v_team_members JSONB;
    v_access JSONB;
BEGIN
    v_projects := check_limit(p_showroom_id, 'projects');
    v_products := check_limit(p_showroom_id, 'products');
    v_storage := check_limit(p_showroom_id, 'storage');
    v_team_members := check_limit(p_showroom_id, 'team_members');
    v_access := check_subscription_access(p_showroom_id);

    RETURN jsonb_build_object(
        'projects', v_projects,
        'products', v_products,
        'storage', v_storage,
        'team_members', v_team_members,
        'subscription', v_access
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- TRIGGERS: Update Usage Counts
-- ============================================

-- Trigger to update product count on insert/delete
CREATE OR REPLACE FUNCTION update_product_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE showrooms
        SET product_count = COALESCE(product_count, 0) + 1
        WHERE id = NEW.showroom_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE showrooms
        SET product_count = GREATEST(0, COALESCE(product_count, 0) - 1)
        WHERE id = OLD.showroom_id;
        RETURN OLD;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_update_product_count_insert ON products;
DROP TRIGGER IF EXISTS trigger_update_product_count_delete ON products;

CREATE TRIGGER trigger_update_product_count_insert
    AFTER INSERT ON products
    FOR EACH ROW
    EXECUTE FUNCTION update_product_count();

CREATE TRIGGER trigger_update_product_count_delete
    AFTER DELETE ON products
    FOR EACH ROW
    EXECUTE FUNCTION update_product_count();

-- Trigger to update team member count on insert/delete
CREATE OR REPLACE FUNCTION update_team_member_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE showrooms
        SET team_member_count = COALESCE(team_member_count, 0) + 1
        WHERE id = NEW.showroom_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE showrooms
        SET team_member_count = GREATEST(1, COALESCE(team_member_count, 0) - 1)
        WHERE id = OLD.showroom_id;
        RETURN OLD;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_update_team_member_count_insert ON showroom_users;
DROP TRIGGER IF EXISTS trigger_update_team_member_count_delete ON showroom_users;

CREATE TRIGGER trigger_update_team_member_count_insert
    AFTER INSERT ON showroom_users
    FOR EACH ROW
    EXECUTE FUNCTION update_team_member_count();

CREATE TRIGGER trigger_update_team_member_count_delete
    AFTER DELETE ON showroom_users
    FOR EACH ROW
    EXECUTE FUNCTION update_team_member_count();
