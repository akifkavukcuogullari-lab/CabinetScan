-- Find which showroom owns the qnexwr files
CREATE OR REPLACE FUNCTION find_qnexwr_showroom()
RETURNS TABLE (
  showroom_id UUID,
  showroom_name TEXT,
  showroom_code TEXT,
  project_count BIGINT,
  sample_file TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.showroom_id,
    s.name as showroom_name,
    s.showroom_code,
    COUNT(*)::BIGINT as project_count,
    (p.webhook_payload->>'files')::TEXT as sample_file
  FROM projects p
  JOIN showrooms s ON p.showroom_id = s.id
  WHERE p.webhook_payload::TEXT LIKE '%qnexwr%'
  GROUP BY p.showroom_id, s.name, s.showroom_code, p.webhook_payload
  LIMIT 5;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute
GRANT EXECUTE ON FUNCTION find_qnexwr_showroom() TO authenticated;
GRANT EXECUTE ON FUNCTION find_qnexwr_showroom() TO service_role;
GRANT EXECUTE ON FUNCTION find_qnexwr_showroom() TO anon;
