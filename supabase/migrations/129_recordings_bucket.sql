-- Create recordings bucket for voice agent call recordings (private, showroom-scoped)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('recordings', 'recordings', false, 52428800, ARRAY['audio/mpeg', 'audio/wav', 'audio/ogg', 'audio/mp4', 'audio/webm'])
ON CONFLICT (id) DO NOTHING;

-- Showroom users can read their own recordings
CREATE POLICY recordings_select ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'recordings'
    AND (
      is_super_admin()
      OR (storage.foldername(name))[1] IN (
        SELECT id::text FROM showrooms
        WHERE id IN (SELECT get_user_showroom_ids())
      )
    )
  );

-- Service role uploads (from edge functions) bypass RLS
-- No insert policy needed for authenticated users since only the webhook uploads
