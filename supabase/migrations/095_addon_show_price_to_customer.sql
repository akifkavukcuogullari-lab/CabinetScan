-- ============================================
-- ADD SHOW PRICE TO CUSTOMER FOR ADDONS
-- Migration: 095_addon_show_price_to_customer
-- Purpose: Allow showroom owners to control if addon prices are shown to customers
-- ============================================

-- Add show_price_to_customer column to showroom_addons
ALTER TABLE showroom_addons
ADD COLUMN IF NOT EXISTS show_price_to_customer BOOLEAN NOT NULL DEFAULT true;

-- Add comment for documentation
COMMENT ON COLUMN showroom_addons.show_price_to_customer IS 'Whether to show the price to customers in the iOS app';
