-- ============================================
-- NEXTLEAN SCAN - ADD AVIF SUPPORT TO LOGOS BUCKET
-- Migration: 011_add_avif_support
-- ============================================

-- Update logos bucket to support AVIF images
UPDATE storage.buckets
SET allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/svg+xml', 'image/webp', 'image/avif']
WHERE id = 'logos';

-- Also update products bucket to support AVIF
UPDATE storage.buckets
SET allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/avif']
WHERE id = 'products';
