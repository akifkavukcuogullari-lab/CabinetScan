-- ============================================
-- REFACTOR: Move storage calculation to SECURITY DEFINER function
-- Keep the view as SECURITY INVOKER (default) for proper RLS behavior
-- Only the storage calculation needs elevated privileges
-- ============================================

-- Create helper function for storage calculation (needs SECURITY DEFINER)
CREATE OR REPLACE FUNCTION get_showroom_storage_bytes(p_showroom_id UUID)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_bytes BIGINT := 0;
  v_showroom_code TEXT;
BEGIN
  -- Get showroom code
  SELECT LOWER(showroom_code) INTO v_showroom_code
  FROM showrooms WHERE id = p_showroom_id;

  IF v_showroom_code IS NULL THEN
    RETURN 0;
  END IF;

  -- Calculate storage from scans bucket
  SELECT COALESCE(SUM((o.metadata->>'size')::BIGINT), 0) INTO v_total_bytes
  FROM storage.objects o
  WHERE o.bucket_id = 'scans'
    AND o.name LIKE v_showroom_code || '/%'
    AND o.metadata->>'size' IS NOT NULL;

  -- Add storage from products bucket
  v_total_bytes := v_total_bytes + COALESCE((
    SELECT SUM((o.metadata->>'size')::BIGINT)
    FROM products p
    JOIN storage.objects o ON o.bucket_id = 'products'
      AND o.metadata->>'size' IS NOT NULL
      AND o.name = SUBSTRING(p.image_url FROM 'products/(.*)')
    WHERE p.showroom_id = p_showroom_id
  ), 0);

  RETURN v_total_bytes;
END;
$$;

-- Create helper function for last month storage (needs SECURITY DEFINER)
CREATE OR REPLACE FUNCTION get_showroom_storage_last_month_bytes(p_showroom_id UUID)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_bytes BIGINT := 0;
  v_showroom_code TEXT;
BEGIN
  SELECT LOWER(showroom_code) INTO v_showroom_code
  FROM showrooms WHERE id = p_showroom_id;

  IF v_showroom_code IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COALESCE(SUM((o.metadata->>'size')::BIGINT), 0) INTO v_total_bytes
  FROM storage.objects o
  WHERE o.bucket_id = 'scans'
    AND o.name LIKE v_showroom_code || '/%'
    AND o.metadata->>'size' IS NOT NULL
    AND o.created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
    AND o.created_at < DATE_TRUNC('month', NOW());

  RETURN v_total_bytes;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION get_showroom_storage_bytes(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_showroom_storage_bytes(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION get_showroom_storage_last_month_bytes(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_showroom_storage_last_month_bytes(UUID) TO service_role;

-- Recreate view as SECURITY INVOKER (default) using the helper functions
DROP VIEW IF EXISTS showroom_usage_summary;

CREATE VIEW showroom_usage_summary AS
SELECT
  s.id,
  s.name,
  s.showroom_code,
  s.email,
  s.subscription_status,
  s.subscription_plan,
  s.created_at,
  -- Project counts use regular tables (RLS applies)
  (SELECT COUNT(*) FROM projects WHERE showroom_id = s.id) AS total_projects,
  (
    SELECT COUNT(*)
    FROM projects
    WHERE showroom_id = s.id
    AND submitted_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
    AND submitted_at < DATE_TRUNC('month', NOW())
  ) AS projects_last_month,
  -- Storage uses SECURITY DEFINER functions
  get_showroom_storage_bytes(s.id) AS total_storage_bytes,
  get_showroom_storage_last_month_bytes(s.id) AS storage_last_month_bytes
FROM showrooms s;

-- Grant access (RLS on showrooms table will apply)
GRANT SELECT ON showroom_usage_summary TO authenticated;
GRANT SELECT ON showroom_usage_summary TO service_role;
GRANT SELECT ON showroom_usage_summary TO anon;

COMMENT ON VIEW showroom_usage_summary IS
'Showroom usage metrics. Uses SECURITY INVOKER (default) - RLS on showrooms applies. Storage calculation uses helper functions with SECURITY DEFINER.';

COMMENT ON FUNCTION get_showroom_storage_bytes IS
'Calculate total storage bytes for a showroom. SECURITY DEFINER needed to access storage.objects.';

COMMENT ON FUNCTION get_showroom_storage_last_month_bytes IS
'Calculate storage bytes from last month for a showroom. SECURITY DEFINER needed to access storage.objects.';
