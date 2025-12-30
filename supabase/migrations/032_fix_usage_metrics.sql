-- ============================================
-- FIX USAGE METRICS CALCULATION
-- Update the view to properly show metrics
-- ============================================

-- Drop the old view
DROP VIEW IF EXISTS showroom_usage_summary;

-- Recreate the view with proper calculations
CREATE OR REPLACE VIEW showroom_usage_summary AS
SELECT
  s.id,
  s.name,
  s.showroom_code,
  s.email,
  s.subscription_status,
  s.subscription_plan,
  s.created_at,
  -- Total projects count
  (SELECT COUNT(*) FROM projects WHERE showroom_id = s.id) AS total_projects,
  -- Last month projects (previous calendar month)
  (
    SELECT COUNT(*)
    FROM projects
    WHERE showroom_id = s.id
    AND submitted_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
    AND submitted_at < DATE_TRUNC('month', NOW())
  ) AS projects_last_month,
  -- Total storage bytes
  COALESCE(
    (
      SELECT SUM((metadata->>'size')::BIGINT)
      FROM storage.objects
      WHERE bucket_id = 'scans'
      AND name LIKE s.id::TEXT || '/%'
      AND metadata->>'size' IS NOT NULL
    ),
    0
  ) AS total_storage_bytes,
  -- Last month storage bytes
  COALESCE(
    (
      SELECT SUM((metadata->>'size')::BIGINT)
      FROM storage.objects
      WHERE bucket_id = 'scans'
      AND name LIKE s.id::TEXT || '/%'
      AND metadata->>'size' IS NOT NULL
      AND created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
      AND created_at < DATE_TRUNC('month', NOW())
    ),
    0
  ) AS storage_last_month_bytes
FROM showrooms s;

-- Grant access
GRANT SELECT ON showroom_usage_summary TO authenticated;
GRANT SELECT ON showroom_usage_summary TO service_role;

-- Update comment
COMMENT ON VIEW showroom_usage_summary IS 'Showroom usage metrics including project counts and storage consumption';
