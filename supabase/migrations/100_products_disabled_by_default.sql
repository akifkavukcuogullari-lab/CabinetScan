-- ============================================
-- PRODUCTS DISABLED BY DEFAULT
-- Migration: 100_products_disabled_by_default
-- Purpose: New products should be disabled (is_active=false) by default
--          Products will be visible in dashboard but not in iOS app until enabled
-- ============================================

-- Change the default value for is_active on products table
ALTER TABLE products
ALTER COLUMN is_active SET DEFAULT false;

-- Note: This does NOT change existing products, only affects new products
