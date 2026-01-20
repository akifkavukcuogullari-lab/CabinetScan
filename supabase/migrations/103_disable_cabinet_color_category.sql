-- ============================================
-- DISABLE CABINET COLOR CATEGORY
-- Migration: 103_disable_cabinet_color_category
-- Purpose: Disable the deprecated Cabinet Color category
--          Colors are now handled as variants under Cabinet Style
-- ============================================

-- Disable the Cabinet Color category
UPDATE categories
SET is_active = false
WHERE slug = 'cabinet-color';

-- Also disable it in all showroom_categories
UPDATE showroom_categories
SET is_enabled = false
WHERE category_id IN (
    SELECT id FROM categories WHERE slug = 'cabinet-color'
);
