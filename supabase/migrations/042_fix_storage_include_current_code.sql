-- ============================================
-- FIX STORAGE CALCULATION - INCLUDE CURRENT SHOWROOM CODE
-- Include both current showroom_code AND folder prefixes from webhook_payload
-- This handles cases where projects don't have webhook_payload populated
-- ============================================

DROP VIEW IF EXISTS showroom_usage_summary;

CREATE OR REPLACE VIEW showroom_usage_summary AS
WITH showroom_folder_prefixes AS (
  -- Combine folder prefixes from project URLs with current showroom code
  SELECT DISTINCT
    s.id as showroom_id,
    LOWER(s.showroom_code) as folder_prefix
  FROM showrooms s

  UNION

  -- Also extract folder prefixes from existing project files (for renamed showrooms)
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
    AND sfp.folder_prefix IS NOT NULL
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
    AND sfp.folder_prefix IS NOT NULL
  GROUP BY sfp.showroom_id
),
showroom_products_storage AS (
  -- Also include product images from the products bucket
  SELECT
    p.showroom_id,
    SUM((o.metadata->>'size')::BIGINT) as total_bytes
  FROM products p
  JOIN storage.objects o ON o.bucket_id = 'products'
    AND o.metadata->>'size' IS NOT NULL
    -- Match product image URLs
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
  -- Total storage bytes: scans + products
  COALESCE(
    (SELECT total_bytes FROM showroom_storage WHERE showroom_id = s.id),
    0
  ) + COALESCE(
    (SELECT total_bytes FROM showroom_products_storage WHERE showroom_id = s.id),
    0
  ) AS total_storage_bytes,
  -- Last month storage bytes (scans only, products don't have timestamps)
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
COMMENT ON VIEW showroom_usage_summary IS 'Showroom usage metrics with storage from scans bucket (using current code + extracted prefixes from projects) and products bucket';
