-- Migration: Add price_catalog_url to showrooms table
-- Allows super admins to upload CSV price catalogs for RAG lookups via n8n

-- Add price_catalog_url column to showrooms table
ALTER TABLE showrooms
ADD COLUMN IF NOT EXISTS price_catalog_url TEXT;

-- Add comment explaining the column
COMMENT ON COLUMN showrooms.price_catalog_url IS
'Public URL to CSV price catalog file for RAG lookups via n8n. Super admin uploads CSV, stored in price-catalogs bucket.';

-- Create price-catalogs bucket (public for n8n access)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'price-catalogs',
  'price-catalogs',
  true,
  10485760,  -- 10MB limit
  ARRAY['text/csv', 'application/csv', 'text/plain', 'application/vnd.ms-excel']
)
ON CONFLICT (id) DO NOTHING;

-- Public read access for all (n8n needs to fetch directly)
CREATE POLICY "Anyone can read price catalogs"
ON storage.objects FOR SELECT
USING (bucket_id = 'price-catalogs');

-- Only super admins can upload price catalogs
CREATE POLICY "Super admins can upload price catalogs"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'price-catalogs'
  AND is_super_admin()
);

-- Only super admins can update price catalogs
CREATE POLICY "Super admins can update price catalogs"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'price-catalogs'
  AND is_super_admin()
);

-- Only super admins can delete price catalogs
CREATE POLICY "Super admins can delete price catalogs"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'price-catalogs'
  AND is_super_admin()
);
