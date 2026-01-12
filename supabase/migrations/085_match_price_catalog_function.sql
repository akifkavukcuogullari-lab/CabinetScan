-- Migration: Add match function for n8n Supabase Vector Store node
-- This function follows n8n's expected naming convention: match_<table_name>

CREATE OR REPLACE FUNCTION match_price_catalog_embeddings(
  query_embedding vector(1536),
  match_count int DEFAULT 5,
  filter jsonb DEFAULT '{}'
)
RETURNS TABLE (
  id uuid,
  content text,
  metadata jsonb,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.search_text as content,
    jsonb_build_object(
      'type', e.type,
      'size', e.size,
      'style', e.style,
      'color', e.color,
      'price', e.price,
      'showroom_id', e.showroom_id
    ) as metadata,
    1 - (e.embedding <=> query_embedding) as similarity
  FROM price_catalog_embeddings e
  WHERE
    -- Filter by showroom_id if provided in filter
    (filter->>'showroom_id' IS NULL OR e.showroom_id = (filter->>'showroom_id')::uuid)
  ORDER BY e.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION match_price_catalog_embeddings TO authenticated;
GRANT EXECUTE ON FUNCTION match_price_catalog_embeddings TO anon;

COMMENT ON FUNCTION match_price_catalog_embeddings IS
'n8n compatible vector search function. Pass showroom_id in filter to scope results: {"showroom_id": "uuid-here"}';
