-- ============================================
-- NEXTLEAN SCAN - STORAGE BUCKETS
-- Migration: 003_storage_buckets
-- ============================================

-- Create buckets
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('logos', 'logos', true, 5242880, ARRAY['image/png', 'image/jpeg', 'image/svg+xml']),
    ('products', 'products', true, 10485760, ARRAY['image/png', 'image/jpeg', 'image/webp']),
    ('scans', 'scans', false, 52428800, ARRAY['model/vnd.usdz+zip', 'image/png', 'image/jpeg', 'application/json']);

-- ============================================
-- LOGOS BUCKET POLICIES (Public read, authenticated write)
-- ============================================

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

-- ============================================
-- PRODUCTS BUCKET POLICIES (Public read, showroom-scoped write)
-- ============================================

-- Anyone can read product images (public bucket)
CREATE POLICY products_public_select ON storage.objects FOR SELECT
    USING (bucket_id = 'products');

-- Authenticated users can upload to their showroom folder
CREATE POLICY products_authenticated_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'products'
        AND (
            is_super_admin()
            OR (storage.foldername(name))[1] IN (
                SELECT id::text FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );

-- Authenticated users can update their showroom product images
CREATE POLICY products_authenticated_update ON storage.objects FOR UPDATE TO authenticated
    USING (
        bucket_id = 'products'
        AND (
            is_super_admin()
            OR (storage.foldername(name))[1] IN (
                SELECT id::text FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );

-- Authenticated users can delete their showroom product images
CREATE POLICY products_authenticated_delete ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'products'
        AND (
            is_super_admin()
            OR (storage.foldername(name))[1] IN (
                SELECT id::text FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );

-- ============================================
-- SCANS BUCKET POLICIES (Private, showroom-scoped)
-- ============================================

-- Authenticated users can read scans from their showrooms
CREATE POLICY scans_authenticated_select ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'scans'
        AND (
            is_super_admin()
            OR (storage.foldername(name))[1] IN (
                SELECT id::text FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );

-- Anon users (iOS app) can upload scans
CREATE POLICY scans_anon_insert ON storage.objects FOR INSERT TO anon
    WITH CHECK (bucket_id = 'scans');

-- Authenticated users can also upload scans
CREATE POLICY scans_authenticated_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'scans');

-- Authenticated users can delete scans from their showrooms
CREATE POLICY scans_authenticated_delete ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'scans'
        AND (
            is_super_admin()
            OR (storage.foldername(name))[1] IN (
                SELECT id::text FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );
