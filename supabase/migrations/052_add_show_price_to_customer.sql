-- Add show_price_to_customer column to products table
-- This controls whether the price is visible to customers in the iOS app during selection

ALTER TABLE products
ADD COLUMN show_price_to_customer BOOLEAN NOT NULL DEFAULT true;

-- Add comment for documentation
COMMENT ON COLUMN products.show_price_to_customer IS 'Controls whether the price is shown to customers in the iOS app during product selection';
