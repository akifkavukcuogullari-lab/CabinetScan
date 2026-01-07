-- Drop orphaned view with SECURITY DEFINER that was left behind during view updates
-- This view is not used anywhere and poses a security issue

DROP VIEW IF EXISTS public.showroom_usage_summary_owner_old;
