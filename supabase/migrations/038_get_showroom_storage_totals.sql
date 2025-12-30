-- Get storage totals by showroom pattern
CREATE OR REPLACE FUNCTION get_showroom_storage_totals()
RETURNS TABLE (
  path_prefix TEXT,
  file_count BIGINT,
  total_bytes TEXT,
  total_gb TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    SPLIT_PART(o.name, '/', 1) as path_prefix,
    COUNT(*)::BIGINT as file_count,
    SUM((o.metadata->>'size')::BIGINT)::TEXT as total_bytes,
    ROUND(SUM((o.metadata->>'size')::BIGINT) / 1024.0 / 1024.0 / 1024.0, 3)::TEXT as total_gb
  FROM storage.objects o
  WHERE o.bucket_id = 'scans'
    AND o.metadata->>'size' IS NOT NULL
  GROUP BY SPLIT_PART(o.name, '/', 1)
  ORDER BY SUM((o.metadata->>'size')::BIGINT) DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute
GRANT EXECUTE ON FUNCTION get_showroom_storage_totals() TO authenticated;
GRANT EXECUTE ON FUNCTION get_showroom_storage_totals() TO service_role;
GRANT EXECUTE ON FUNCTION get_showroom_storage_totals() TO anon;
