-- Move show_price_to_customer from products to showroom_categories (category level)
-- This controls whether prices are shown for ALL products in a category

-- Add column to showroom_categories
ALTER TABLE showroom_categories
ADD COLUMN show_price_to_customer BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN showroom_categories.show_price_to_customer IS 'Controls whether prices are shown to customers in the iOS app for all products in this category';

-- Remove the column from products table (no longer needed at product level)
ALTER TABLE products
DROP COLUMN IF EXISTS show_price_to_customer;
