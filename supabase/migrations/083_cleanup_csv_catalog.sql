-- Migration: Cleanup CSV-based price catalog implementation
-- Replacing with vector database approach

-- Remove price_catalog_url column from showrooms
ALTER TABLE showrooms DROP COLUMN IF EXISTS price_catalog_url;

-- Remove storage bucket policies
DROP POLICY IF EXISTS "Anyone can read price catalogs" ON storage.objects;
DROP POLICY IF EXISTS "Super admins can upload price catalogs" ON storage.objects;
DROP POLICY IF EXISTS "Super admins can update price catalogs" ON storage.objects;
DROP POLICY IF EXISTS "Super admins can delete price catalogs" ON storage.objects;

-- Remove storage bucket
DELETE FROM storage.buckets WHERE id = 'price-catalogs';
