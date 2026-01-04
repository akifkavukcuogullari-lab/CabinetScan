-- ============================================
-- ADD IMAGE SUPPORT TO CUSTOM ADDONS
-- ============================================

-- Add image_url field to showroom_addons
ALTER TABLE showroom_addons
ADD COLUMN image_url TEXT;

-- Update default addon with an image if it exists
UPDATE showroom_addons
SET image_url = NULL
WHERE question = 'Add trash can?';
