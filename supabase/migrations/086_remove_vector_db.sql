-- Migration: Remove vector database approach, use simple CSV table instead

-- Drop the match function (for n8n)
DROP FUNCTION IF EXISTS match_price_catalog_embeddings(vector(1536), int, jsonb);

-- Drop the search function
DROP FUNCTION IF EXISTS search_price_catalog(uuid, vector(1536), int);

-- Drop the vector table
DROP TABLE IF EXISTS price_catalog_embeddings;

-- Note: We keep the vector extension as it might be used elsewhere
-- DROP EXTENSION IF EXISTS vector;

-- Create simple price catalog table (no embeddings)
CREATE TABLE price_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

  -- CSV fields
  type TEXT NOT NULL,
  size TEXT,
  style TEXT,
  color TEXT,
  price DECIMAL(10,2),

  -- Additional fields for flexibility
  description TEXT,
  sku TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for showroom filtering
CREATE INDEX price_catalog_showroom_idx ON price_catalog(showroom_id);

-- Index for type lookups
CREATE INDEX price_catalog_type_idx ON price_catalog(showroom_id, type);

-- RLS policies
ALTER TABLE price_catalog ENABLE ROW LEVEL SECURITY;

-- Super admins can manage all catalog entries
CREATE POLICY "Super admins can manage all price catalogs"
ON price_catalog
FOR ALL TO authenticated
USING (is_super_admin())
WITH CHECK (is_super_admin());

-- Showroom owners can view their own catalog
CREATE POLICY "Showroom owners can view own catalog"
ON price_catalog
FOR SELECT TO authenticated
USING (has_showroom_access(showroom_id));

-- Anyone can read for price lookups (service role / n8n access)
CREATE POLICY "Anyone can read price catalogs for lookups"
ON price_catalog
FOR SELECT
USING (true);

-- Simple search function for n8n (text-based matching)
CREATE OR REPLACE FUNCTION search_price_catalog_simple(
  p_showroom_id UUID,
  p_search_text TEXT DEFAULT NULL,
  p_type TEXT DEFAULT NULL,
  p_limit INT DEFAULT 10
)
RETURNS TABLE (
  id UUID,
  type TEXT,
  size TEXT,
  style TEXT,
  color TEXT,
  price DECIMAL,
  description TEXT,
  sku TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    pc.id,
    pc.type,
    pc.size,
    pc.style,
    pc.color,
    pc.price,
    pc.description,
    pc.sku
  FROM price_catalog pc
  WHERE pc.showroom_id = p_showroom_id
    AND (p_type IS NULL OR pc.type ILIKE '%' || p_type || '%')
    AND (p_search_text IS NULL OR
         pc.type ILIKE '%' || p_search_text || '%' OR
         pc.size ILIKE '%' || p_search_text || '%' OR
         pc.style ILIKE '%' || p_search_text || '%' OR
         pc.color ILIKE '%' || p_search_text || '%' OR
         pc.description ILIKE '%' || p_search_text || '%')
  ORDER BY pc.type, pc.size
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION search_price_catalog_simple TO authenticated;
GRANT EXECUTE ON FUNCTION search_price_catalog_simple TO anon;

COMMENT ON TABLE price_catalog IS
'Simple price catalog table. Admin uploads CSV, data stored directly without embeddings. n8n queries via search_price_catalog_simple function or direct SQL.';
