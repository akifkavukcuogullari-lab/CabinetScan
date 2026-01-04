-- Get sample file paths to debug storage structure
CREATE OR REPLACE FUNCTION get_storage_file_samples()
RETURNS TABLE (
  bucket_id TEXT,
  file_path TEXT,
  size_bytes TEXT,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    o.bucket_id,
    o.name as file_path,
    o.metadata->>'size' as size_bytes,
    o.created_at
  FROM storage.objects o
  WHERE o.bucket_id IN ('scans', 'products', 'logos')
  ORDER BY (o.metadata->>'size')::BIGINT DESC NULLS LAST
  LIMIT 30;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute
GRANT EXECUTE ON FUNCTION get_storage_file_samples() TO authenticated;
GRANT EXECUTE ON FUNCTION get_storage_file_samples() TO service_role;
GRANT EXECUTE ON FUNCTION get_storage_file_samples() TO anon;
