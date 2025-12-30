-- ============================================
-- FIX STORAGE CALCULATION USING PROJECTS TABLE
-- Calculate storage by finding all folder prefixes used by each showroom's projects
-- This captures ALL files regardless of showroom code changes or folder naming
-- ============================================

DROP VIEW IF EXISTS showroom_usage_summary;

CREATE OR REPLACE VIEW showroom_usage_summary AS
WITH showroom_folder_prefixes AS (
  -- Extract unique folder prefixes used by each showroom from project file URLs
  SELECT DISTINCT
    p.showroom_id,
    SPLIT_PART(
      SUBSTRING(
        COALESCE(
          p.webhook_payload->'files'->>'video',
          p.webhook_payload->'files'->>'scan_3d',
          p.webhook_payload->'files'->>'floor_plan',
          p.webhook_payload->'files'->>'video_thumbnail',
          p.webhook_payload->'files'->'visualization_photos'->>0
        )
        FROM 'scans/([^/]+)/'
      ),
      '/',
      1
    ) as folder_prefix
  FROM projects p
  WHERE p.webhook_payload IS NOT NULL
    AND p.webhook_payload->'files' IS NOT NULL
),
showroom_storage AS (
  -- Sum storage for all files in folders used by each showroom
  SELECT
    sfp.showroom_id,
    SUM((o.metadata->>'size')::BIGINT) as total_bytes
  FROM showroom_folder_prefixes sfp
  JOIN storage.objects o ON o.bucket_id = 'scans'
    AND o.name LIKE sfp.folder_prefix || '/%'
  WHERE o.metadata->>'size' IS NOT NULL
  GROUP BY sfp.showroom_id
),
showroom_storage_last_month AS (
  -- Sum storage for files created last month
  SELECT
    sfp.showroom_id,
    SUM((o.metadata->>'size')::BIGINT) as total_bytes
  FROM showroom_folder_prefixes sfp
  JOIN storage.objects o ON o.bucket_id = 'scans'
    AND o.name LIKE sfp.folder_prefix || '/%'
    AND o.created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
    AND o.created_at < DATE_TRUNC('month', NOW())
  WHERE o.metadata->>'size' IS NOT NULL
  GROUP BY sfp.showroom_id
)
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
  -- Total storage bytes from all folders used by this showroom
  COALESCE(
    (SELECT total_bytes FROM showroom_storage WHERE showroom_id = s.id),
    0
  ) AS total_storage_bytes,
  -- Last month storage bytes
  COALESCE(
    (SELECT total_bytes FROM showroom_storage_last_month WHERE showroom_id = s.id),
    0
  ) AS storage_last_month_bytes
FROM showrooms s;

-- Grant access
GRANT SELECT ON showroom_usage_summary TO authenticated;
GRANT SELECT ON showroom_usage_summary TO service_role;
GRANT SELECT ON showroom_usage_summary TO anon;

-- Update comment
COMMENT ON VIEW showroom_usage_summary IS 'Showroom usage metrics with storage calculated by analyzing project file URLs to find all folder prefixes used by each showroom, capturing files regardless of showroom code changes';
