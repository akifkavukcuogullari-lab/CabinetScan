-- Migration: Color Coefficient-Based Pricing
-- This migration adds coefficient-based pricing for products and addons
-- based on the selected Cabinet Model color variant.

-- 1. Add price coefficient to product_variants (for Cabinet Model colors)
ALTER TABLE product_variants
ADD COLUMN price_coefficient DECIMAL(4,2) NOT NULL DEFAULT 1.00;

-- 2. Add toggle to products (to opt-in to coefficient pricing)
ALTER TABLE products
ADD COLUMN use_color_coefficient BOOLEAN NOT NULL DEFAULT false;

-- 3. Add toggle to showroom_addons (to opt-in to coefficient pricing)
ALTER TABLE showroom_addons
ADD COLUMN use_color_coefficient BOOLEAN NOT NULL DEFAULT false;

-- 4. Add snapshot columns for historical data

-- For product selections
ALTER TABLE project_selections
ADD COLUMN coefficient_applied DECIMAL(4,2);

-- For addon selections
ALTER TABLE project_addon_selections
ADD COLUMN coefficient_applied DECIMAL(4,2);

-- Add comments for documentation
COMMENT ON COLUMN product_variants.price_coefficient IS 'Price multiplier for this color variant (e.g., 1.0 for White, 1.3 for Navy Blue)';
COMMENT ON COLUMN products.use_color_coefficient IS 'If true, product price is multiplied by the selected Cabinet Model color coefficient';
COMMENT ON COLUMN showroom_addons.use_color_coefficient IS 'If true, addon price is multiplied by the selected Cabinet Model color coefficient';
COMMENT ON COLUMN project_selections.coefficient_applied IS 'Snapshot of the coefficient used at time of selection';
COMMENT ON COLUMN project_addon_selections.coefficient_applied IS 'Snapshot of the coefficient used at time of selection';
