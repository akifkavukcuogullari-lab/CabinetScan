-- ============================================
-- FIX STORAGE CALCULATION TO USE SHOWROOM CODE
-- Files are stored under showroom_code (e.g., 'qnexwr'), not showroom UUID
-- ============================================

-- Drop and recreate the view with correct path matching
DROP VIEW IF EXISTS showroom_usage_summary;

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
  -- Total storage bytes - using LOWERCASE showroom_code
  COALESCE(
    (
      SELECT SUM(
        CASE
          WHEN metadata->>'size' IS NOT NULL AND metadata->>'size' != ''
          THEN (metadata->>'size')::BIGINT
          ELSE 0
        END
      )
      FROM storage.objects
      WHERE bucket_id = 'scans'
      AND name LIKE LOWER(s.showroom_code) || '/%'
    ),
    0
  ) AS total_storage_bytes,
  -- Last month storage bytes
  COALESCE(
    (
      SELECT SUM(
        CASE
          WHEN metadata->>'size' IS NOT NULL AND metadata->>'size' != ''
          THEN (metadata->>'size')::BIGINT
          ELSE 0
        END
      )
      FROM storage.objects
      WHERE bucket_id = 'scans'
      AND name LIKE LOWER(s.showroom_code) || '/%'
      AND created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
      AND created_at < DATE_TRUNC('month', NOW())
    ),
    0
  ) AS storage_last_month_bytes
FROM showrooms s;

-- Grant access
GRANT SELECT ON showroom_usage_summary TO authenticated;
GRANT SELECT ON showroom_usage_summary TO service_role;
GRANT SELECT ON showroom_usage_summary TO anon;

-- Update comment
COMMENT ON VIEW showroom_usage_summary IS 'Showroom usage metrics with storage calculated by showroom_code (files stored as scans/{lowercase_showroom_code}/*)';
