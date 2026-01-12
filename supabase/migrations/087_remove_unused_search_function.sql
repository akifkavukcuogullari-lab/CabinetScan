-- Migration: Remove unused search_price_catalog_simple function
-- This function was created for n8n but is not being used anywhere

DROP FUNCTION IF EXISTS search_price_catalog_simple(UUID, TEXT, TEXT, INT);
