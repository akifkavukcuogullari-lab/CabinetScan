-- ============================================
-- FORCE SECURITY INVOKER on showroom_usage_summary view
-- Explicitly set security_invoker = true to ensure RLS applies
-- ============================================

DROP VIEW IF EXISTS showroom_usage_summary;

CREATE VIEW showroom_usage_summary
WITH (security_invoker = true)  -- Explicitly force SECURITY INVOKER
AS
SELECT
  s.id,
  s.name,
  s.showroom_code,
  s.email,
  s.subscription_status,
  s.subscription_plan,
  s.created_at,
  (SELECT COUNT(*) FROM projects WHERE showroom_id = s.id) AS total_projects,
  (
    SELECT COUNT(*)
    FROM projects
    WHERE showroom_id = s.id
    AND submitted_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
    AND submitted_at < DATE_TRUNC('month', NOW())
  ) AS projects_last_month,
  get_showroom_storage_bytes(s.id) AS total_storage_bytes,
  get_showroom_storage_last_month_bytes(s.id) AS storage_last_month_bytes
FROM showrooms s;

GRANT SELECT ON showroom_usage_summary TO authenticated;
GRANT SELECT ON showroom_usage_summary TO service_role;
GRANT SELECT ON showroom_usage_summary TO anon;

COMMENT ON VIEW showroom_usage_summary IS
'Showroom usage metrics with SECURITY INVOKER. Storage uses helper functions with SECURITY DEFINER.';
