-- Debug function to see what folder prefixes are extracted for each showroom
CREATE OR REPLACE FUNCTION debug_showroom_folders()
RETURNS TABLE (
  showroom_id UUID,
  showroom_name TEXT,
  showroom_code TEXT,
  folder_prefixes TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.id,
    s.name,
    s.showroom_code,
    STRING_AGG(DISTINCT
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
      ),
      ', '
    ) as folder_prefixes
  FROM showrooms s
  LEFT JOIN projects p ON p.showroom_id = s.id
    AND p.webhook_payload IS NOT NULL
    AND p.webhook_payload->'files' IS NOT NULL
  GROUP BY s.id, s.name, s.showroom_code
  ORDER BY s.name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute
GRANT EXECUTE ON FUNCTION debug_showroom_folders() TO authenticated;
GRANT EXECUTE ON FUNCTION debug_showroom_folders() TO service_role;
GRANT EXECUTE ON FUNCTION debug_showroom_folders() TO anon;
