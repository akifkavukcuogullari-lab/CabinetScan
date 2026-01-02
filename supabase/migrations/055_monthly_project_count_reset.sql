-- ============================================
-- NEXTLEAN SCAN - MONTHLY PROJECT COUNT RESET
-- Migration: 055_monthly_project_count_reset
-- Purpose: Reset project_count_this_period on the 1st of every month
-- ============================================

-- Enable pg_cron extension (may already be enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ============================================
-- FUNCTION: Reset Monthly Project Counts
-- Resets project_count_this_period to 0 for all showrooms
-- ============================================
CREATE OR REPLACE FUNCTION reset_monthly_project_counts()
RETURNS void AS $$
DECLARE
    v_reset_count INT;
BEGIN
    -- Reset all showroom project counts
    UPDATE showrooms
    SET
        project_count_this_period = 0,
        period_start_date = CURRENT_DATE
    WHERE subscription_status IN ('trial', 'active');

    GET DIAGNOSTICS v_reset_count = ROW_COUNT;

    -- Log the reset
    RAISE NOTICE 'Monthly project count reset completed. % showrooms updated.', v_reset_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- CRON JOB: Schedule Monthly Reset
-- Runs at 00:00 UTC on the 1st of every month
-- ============================================

-- Remove existing job if it exists (to avoid duplicates)
SELECT cron.unschedule('monthly-project-count-reset')
WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'monthly-project-count-reset'
);

-- Schedule the monthly reset job
-- Cron expression: minute hour day-of-month month day-of-week
-- '0 0 1 * *' = At 00:00 on day 1 of every month
SELECT cron.schedule(
    'monthly-project-count-reset',
    '0 0 1 * *',
    'SELECT reset_monthly_project_counts()'
);

-- ============================================
-- FUNCTION: Manual Reset (for admin use)
-- Allows super admin to manually reset a specific showroom
-- ============================================
CREATE OR REPLACE FUNCTION reset_showroom_project_count(p_showroom_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE showrooms
    SET
        project_count_this_period = 0,
        period_start_date = CURRENT_DATE
    WHERE id = p_showroom_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION reset_monthly_project_counts() TO service_role;
GRANT EXECUTE ON FUNCTION reset_showroom_project_count(UUID) TO service_role;

-- ============================================
-- COMMENT
-- ============================================
COMMENT ON FUNCTION reset_monthly_project_counts() IS 'Resets project_count_this_period to 0 for all active showrooms. Scheduled to run on 1st of each month.';
COMMENT ON FUNCTION reset_showroom_project_count(UUID) IS 'Manually reset project count for a specific showroom (admin use).';
