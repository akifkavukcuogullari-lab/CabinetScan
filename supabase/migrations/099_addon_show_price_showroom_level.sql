-- ============================================
-- ADDON SHOW PRICE AT SHOWROOM LEVEL
-- Migration: 099_addon_show_price_showroom_level
-- Purpose: Move addon price visibility to showroom level (affects all addons)
-- ============================================

-- Add showroom-level setting for addon price visibility
ALTER TABLE showrooms
ADD COLUMN IF NOT EXISTS addon_show_price_to_customer BOOLEAN NOT NULL DEFAULT false;

-- Add comment for documentation
COMMENT ON COLUMN showrooms.addon_show_price_to_customer IS 'Whether to show addon prices to customers in the iOS app (affects all addons)';

-- Drop the per-addon column as it's no longer needed
-- Note: We keep the column for now in case we need to rollback
-- ALTER TABLE showroom_addons DROP COLUMN IF EXISTS show_price_to_customer;
