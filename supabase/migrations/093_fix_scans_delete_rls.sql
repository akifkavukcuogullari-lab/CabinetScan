-- ============================================
-- FIX: Scans bucket delete RLS policy
-- The original policy checked for showroom ID as folder name,
-- but files are stored with showroom_code as folder prefix.
-- ============================================

-- Drop the old broken policy
DROP POLICY IF EXISTS scans_authenticated_delete ON storage.objects;

-- Create new policy that checks showroom_code instead of id
CREATE POLICY scans_authenticated_delete ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'scans'
        AND (
            is_super_admin()
            OR LOWER((storage.foldername(name))[1]) IN (
                SELECT LOWER(showroom_code) FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );

-- Note: Files are stored as scans/{lowercase_showroom_code}/...
-- The policy matches against showroom_code to allow proper deletion
