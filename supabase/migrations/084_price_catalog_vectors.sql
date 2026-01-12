-- Migration: Add pgvector support for price catalog semantic search
-- Enables AI-powered price lookups via n8n

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create vector table for price catalog embeddings
CREATE TABLE price_catalog_embeddings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

  -- Original CSV fields
  type TEXT NOT NULL,
  size TEXT,
  style TEXT,
  color TEXT,
  price DECIMAL(10,2),

  -- Vector embedding (1536 dims for OpenAI text-embedding-3-small)
  embedding vector(1536),

  -- Searchable text used for embedding generation
  search_text TEXT NOT NULL,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for showroom filtering (used before vector search)
CREATE INDEX price_catalog_showroom_idx ON price_catalog_embeddings(showroom_id);

-- Note: ivfflat index requires data to exist first
-- We'll create it after initial data load or use HNSW instead
-- For now, exact nearest neighbor search will be used

-- RLS policies
ALTER TABLE price_catalog_embeddings ENABLE ROW LEVEL SECURITY;

-- Super admins can manage all catalog entries
CREATE POLICY "Super admins can manage all price catalogs"
ON price_catalog_embeddings
FOR ALL TO authenticated
USING (is_super_admin())
WITH CHECK (is_super_admin());

-- Anyone can read for price lookups (n8n service role access)
CREATE POLICY "Anyone can read price catalogs for lookups"
ON price_catalog_embeddings
FOR SELECT
USING (true);

-- Function for semantic search (called by n8n)
CREATE OR REPLACE FUNCTION search_price_catalog(
  p_showroom_id UUID,
  p_query_embedding vector(1536),
  p_limit INT DEFAULT 5
)
RETURNS TABLE (
  type TEXT,
  size TEXT,
  style TEXT,
  color TEXT,
  price DECIMAL,
  similarity FLOAT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.type,
    e.size,
    e.style,
    e.color,
    e.price,
    1 - (e.embedding <=> p_query_embedding) as similarity
  FROM price_catalog_embeddings e
  WHERE e.showroom_id = p_showroom_id
  ORDER BY e.embedding <=> p_query_embedding
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated and anon (for n8n service role)
GRANT EXECUTE ON FUNCTION search_price_catalog TO authenticated;
GRANT EXECUTE ON FUNCTION search_price_catalog TO anon;

-- Add comment for documentation
COMMENT ON TABLE price_catalog_embeddings IS
'Stores price catalog items with vector embeddings for semantic search. Admin uploads CSV, system generates embeddings via OpenAI, n8n queries via search_price_catalog function.';

COMMENT ON FUNCTION search_price_catalog IS
'Semantic search over price catalog. Pass showroom_id, query embedding (1536 dims from OpenAI), and result limit. Returns matching items sorted by similarity.';
