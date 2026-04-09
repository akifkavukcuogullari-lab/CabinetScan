-- Allow authenticated users to update (overwrite) files in scans bucket
-- Needed for whiteboard edit (re-save overwrites existing drawing file)
CREATE POLICY scans_authenticated_update ON storage.objects FOR UPDATE TO authenticated
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
