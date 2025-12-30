-- Temporary helper function to debug storage
CREATE OR REPLACE FUNCTION debug_storage_summary()
RETURNS TABLE (
  bucket_id TEXT,
  file_count BIGINT,
  total_bytes BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    o.bucket_id,
    COUNT(*)::BIGINT as file_count,
    COALESCE(SUM((o.metadata->>'size')::BIGINT), 0) as total_bytes
  FROM storage.objects o
  WHERE o.metadata->>'size' IS NOT NULL
  GROUP BY o.bucket_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION debug_storage_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION debug_storage_summary() TO service_role;
GRANT EXECUTE ON FUNCTION debug_storage_summary() TO anon;
