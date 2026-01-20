-- ============================================
-- RENAME CABINET MODEL TO CABINET STYLE
-- Migration: 102_rename_cabinet_model_to_style
-- Purpose: Update category name from "Cabinet Model" to "Cabinet Style"
-- ============================================

-- Update the category name (keep slug as cabinet-model for backwards compatibility)
UPDATE categories
SET name = 'Cabinet Style'
WHERE slug = 'cabinet-model';

-- Note: The slug remains 'cabinet-model' to avoid breaking existing references
