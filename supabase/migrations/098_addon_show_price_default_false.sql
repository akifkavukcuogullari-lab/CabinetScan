-- ============================================
-- CHANGE ADDON SHOW PRICE DEFAULT TO FALSE
-- Migration: 098_addon_show_price_default_false
-- Purpose: Change default value for show_price_to_customer to false
-- ============================================

-- Change the default value from true to false
ALTER TABLE showroom_addons
ALTER COLUMN show_price_to_customer SET DEFAULT false;

-- Update existing addons to false (optional - only if you want to reset all existing)
-- Uncomment below if needed:
-- UPDATE showroom_addons SET show_price_to_customer = false;
