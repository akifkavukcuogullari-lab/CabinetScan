-- ============================================
-- FIX VIEW SECURITY SETTINGS
-- Make SECURITY DEFINER explicit for views that need to access storage.objects
-- These views require elevated privileges to read from storage tables
-- ============================================

-- Recreate showroom_usage_summary with explicit SECURITY DEFINER
-- This is REQUIRED because the view queries storage.objects which regular users cannot access
DROP VIEW IF EXISTS showroom_usage_summary;

CREATE VIEW showroom_usage_summary
WITH (security_invoker = false)  -- Explicitly set SECURITY DEFINER behavior
AS
WITH showroom_folder_prefixes AS (
  SELECT DISTINCT
    s.id as showroom_id,
    LOWER(s.showroom_code) as folder_prefix
  FROM showrooms s
  UNION
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
  SELECT
    sfp.showroom_id,
    SUM((o.metadata->>'size')::BIGINT) as total_bytes
  FROM showroom_folder_prefixes sfp
  JOIN storage.objects o ON o.bucket_id = 'scans'
    AND o.name LIKE sfp.folder_prefix || '/%'
  WHERE o.metadata->>'size' IS NOT NULL
    AND sfp.folder_prefix IS NOT NULL
  GROUP BY sfp.showroom_id
),
showroom_storage_last_month AS (
  SELECT
    sfp.showroom_id,
    SUM((o.metadata->>'size')::BIGINT) as total_bytes
  FROM showroom_folder_prefixes sfp
  JOIN storage.objects o ON o.bucket_id = 'scans'
    AND o.name LIKE sfp.folder_prefix || '/%'
    AND o.created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
    AND o.created_at < DATE_TRUNC('month', NOW())
  WHERE o.metadata->>'size' IS NOT NULL
    AND sfp.folder_prefix IS NOT NULL
  GROUP BY sfp.showroom_id
),
showroom_products_storage AS (
  SELECT
    p.showroom_id,
    SUM((o.metadata->>'size')::BIGINT) as total_bytes
  FROM products p
  JOIN storage.objects o ON o.bucket_id = 'products'
    AND o.metadata->>'size' IS NOT NULL
    AND (o.name = SUBSTRING(p.image_url FROM 'products/(.*)'))
  GROUP BY p.showroom_id
)
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
  COALESCE(
    (SELECT total_bytes FROM showroom_storage WHERE showroom_id = s.id),
    0
  ) + COALESCE(
    (SELECT total_bytes FROM showroom_products_storage WHERE showroom_id = s.id),
    0
  ) AS total_storage_bytes,
  COALESCE(
    (SELECT total_bytes FROM showroom_storage_last_month WHERE showroom_id = s.id),
    0
  ) AS storage_last_month_bytes
FROM showrooms s;

-- Grant access
GRANT SELECT ON showroom_usage_summary TO authenticated;
GRANT SELECT ON showroom_usage_summary TO service_role;
GRANT SELECT ON showroom_usage_summary TO anon;

-- Document why SECURITY DEFINER is needed
COMMENT ON VIEW showroom_usage_summary IS
'Showroom usage metrics. Uses SECURITY DEFINER (security_invoker=false) because it queries storage.objects which regular users cannot directly access.';
