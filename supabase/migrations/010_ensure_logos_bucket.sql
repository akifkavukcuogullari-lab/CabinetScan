-- ============================================
-- NEXTLEAN SCAN - ENSURE LOGOS BUCKET EXISTS
-- Migration: 010_ensure_logos_bucket
-- ============================================

-- Ensure logos bucket exists (use ON CONFLICT to handle if it already exists)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('logos', 'logos', true, 5242880, ARRAY['image/png', 'image/jpeg', 'image/svg+xml', 'image/webp', 'image/avif'])
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/svg+xml', 'image/webp', 'image/avif'];

-- Recreate storage policies (drop if exists first to avoid conflicts)
DROP POLICY IF EXISTS logos_public_select ON storage.objects;
DROP POLICY IF EXISTS logos_authenticated_insert ON storage.objects;
DROP POLICY IF EXISTS logos_authenticated_update ON storage.objects;
DROP POLICY IF EXISTS logos_authenticated_delete ON storage.objects;

-- Anyone can read logos (public bucket)
CREATE POLICY logos_public_select ON storage.objects FOR SELECT
    USING (bucket_id = 'logos');

-- Authenticated users can upload to their showroom folder
CREATE POLICY logos_authenticated_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'logos'
        AND (
            is_super_admin()
            OR (storage.foldername(name))[1] IN (
                SELECT id::text FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );

-- Authenticated users can update their showroom logos
CREATE POLICY logos_authenticated_update ON storage.objects FOR UPDATE TO authenticated
    USING (
        bucket_id = 'logos'
        AND (
            is_super_admin()
            OR (storage.foldername(name))[1] IN (
                SELECT id::text FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );

-- Authenticated users can delete their showroom logos
CREATE POLICY logos_authenticated_delete ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'logos'
        AND (
            is_super_admin()
            OR (storage.foldername(name))[1] IN (
                SELECT id::text FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );
