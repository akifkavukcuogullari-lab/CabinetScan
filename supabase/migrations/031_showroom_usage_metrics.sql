-- ============================================
-- SHOWROOM USAGE METRICS
-- Track project counts and storage usage for each showroom
-- ============================================

-- Function to get showroom usage metrics
CREATE OR REPLACE FUNCTION get_showroom_usage_metrics(p_showroom_id UUID)
RETURNS TABLE (
  total_projects BIGINT,
  projects_last_month BIGINT,
  total_storage_bytes BIGINT,
  storage_last_month_bytes BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH project_stats AS (
    SELECT
      COUNT(*) AS total_projects,
      COUNT(*) FILTER (
        WHERE submitted_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
        AND submitted_at < DATE_TRUNC('month', NOW())
      ) AS projects_last_month
    FROM projects
    WHERE showroom_id = p_showroom_id
  ),
  storage_stats AS (
    SELECT
      COALESCE(SUM(
        CASE
          WHEN obj.metadata->>'size' IS NOT NULL
          THEN (obj.metadata->>'size')::BIGINT
          ELSE 0
        END
      ), 0) AS total_storage,
      COALESCE(SUM(
        CASE
          WHEN obj.created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
          AND obj.created_at < DATE_TRUNC('month', NOW())
          AND obj.metadata->>'size' IS NOT NULL
          THEN (obj.metadata->>'size')::BIGINT
          ELSE 0
        END
      ), 0) AS storage_last_month
    FROM storage.objects obj
    WHERE obj.bucket_id = 'scans'
    AND obj.name LIKE p_showroom_id::TEXT || '/%'
  )
  SELECT
    ps.total_projects,
    ps.projects_last_month,
    ss.total_storage,
    ss.storage_last_month
  FROM project_stats ps
  CROSS JOIN storage_stats ss;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create a view for all showrooms with usage metrics
CREATE OR REPLACE VIEW showroom_usage_summary AS
SELECT
  s.id,
  s.name,
  s.showroom_code,
  s.email,
  s.subscription_status,
  s.subscription_plan,
  s.created_at,
  COALESCE(p.total_projects, 0) AS total_projects,
  COALESCE(p.projects_last_month, 0) AS projects_last_month,
  COALESCE(st.total_storage_bytes, 0) AS total_storage_bytes,
  COALESCE(st.storage_last_month_bytes, 0) AS storage_last_month_bytes
FROM showrooms s
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) AS total_projects,
    COUNT(*) FILTER (
      WHERE submitted_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
      AND submitted_at < DATE_TRUNC('month', NOW())
    ) AS projects_last_month
  FROM projects
  WHERE showroom_id = s.id
) p ON true
LEFT JOIN LATERAL (
  SELECT
    COALESCE(SUM(
      CASE
        WHEN obj.metadata->>'size' IS NOT NULL
        THEN (obj.metadata->>'size')::BIGINT
        ELSE 0
      END
    ), 0) AS total_storage_bytes,
    COALESCE(SUM(
      CASE
        WHEN obj.created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
        AND obj.created_at < DATE_TRUNC('month', NOW())
        AND obj.metadata->>'size' IS NOT NULL
        THEN (obj.metadata->>'size')::BIGINT
        ELSE 0
      END
    ), 0) AS storage_last_month_bytes
  FROM storage.objects obj
  WHERE obj.bucket_id = 'scans'
  AND obj.name LIKE s.id::TEXT || '/%'
) st ON true;

-- Grant access to the view for authenticated users
GRANT SELECT ON showroom_usage_summary TO authenticated;

-- Comments
COMMENT ON FUNCTION get_showroom_usage_metrics IS 'Returns project count and storage usage metrics for a specific showroom';
COMMENT ON VIEW showroom_usage_summary IS 'Aggregated view of all showrooms with their usage metrics including project counts and storage consumption';
