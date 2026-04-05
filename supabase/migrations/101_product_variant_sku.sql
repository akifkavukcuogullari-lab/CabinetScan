-- ============================================
-- PRODUCT VARIANT SKU
-- Migration: 101_product_variant_sku
-- Purpose: Add SKU field to product_variants for color/variant tracking
-- ============================================

-- Add SKU column to product_variants table
ALTER TABLE product_variants
ADD COLUMN IF NOT EXISTS sku TEXT;

-- Add unique constraint for SKU within a product
-- (same SKU can exist for different products, but must be unique per product)
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variants_sku_unique
ON product_variants(product_id, sku)
WHERE sku IS NOT NULL;

COMMENT ON COLUMN product_variants.sku IS 'SKU code for this color/variant, unique within the product';
