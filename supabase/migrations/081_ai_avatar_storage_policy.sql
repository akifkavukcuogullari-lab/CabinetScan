-- Migration: AI Avatar Storage Policy
-- Allows showroom owners to upload AI assistant avatars to the logos bucket

-- Allow showroom owners to upload AI avatars
CREATE POLICY "Showroom owners can upload AI avatars"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'logos'
  AND (storage.foldername(name))[1] = 'ai-avatars'
  AND EXISTS (
    SELECT 1 FROM showroom_users su
    WHERE su.user_id = auth.uid()
    AND su.is_active = true
  )
);

-- Allow showroom owners to update their AI avatars
CREATE POLICY "Showroom owners can update AI avatars"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'logos'
  AND (storage.foldername(name))[1] = 'ai-avatars'
  AND EXISTS (
    SELECT 1 FROM showroom_users su
    WHERE su.user_id = auth.uid()
    AND su.is_active = true
  )
);

-- Allow showroom owners to delete their AI avatars
CREATE POLICY "Showroom owners can delete AI avatars"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'logos'
  AND (storage.foldername(name))[1] = 'ai-avatars'
  AND EXISTS (
    SELECT 1 FROM showroom_users su
    WHERE su.user_id = auth.uid()
    AND su.is_active = true
  )
);

-- Allow public read access to AI avatars (they're displayed in the iOS app)
CREATE POLICY "Public can read AI avatars"
ON storage.objects FOR SELECT
TO public
USING (
  bucket_id = 'logos'
  AND (storage.foldername(name))[1] = 'ai-avatars'
);
