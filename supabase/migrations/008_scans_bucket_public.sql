-- Migration: Make scans bucket public for 3D viewer access
-- The scans bucket needs to be public so the dashboard can display USDZ files in the 3D viewer
-- Previously it was private which broke the viewer functionality

-- Update bucket to be public
UPDATE storage.buckets
SET public = true
WHERE id = 'scans';

-- Add policy for public read access (anyone can view scans via public URL)
-- Drop existing policy first if it exists, then recreate
DO $$
BEGIN
    -- Check if policy exists and drop it
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'scans_public_select'
    ) THEN
        DROP POLICY scans_public_select ON storage.objects;
    END IF;
END $$;

CREATE POLICY scans_public_select ON storage.objects FOR SELECT
    USING (bucket_id = 'scans');
