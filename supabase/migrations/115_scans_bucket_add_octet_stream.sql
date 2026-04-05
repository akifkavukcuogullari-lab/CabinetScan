-- Allow application/octet-stream in scans bucket for whiteboard drawing data (PKDrawing binary)
UPDATE storage.buckets
SET allowed_mime_types = ARRAY['model/vnd.usdz+zip', 'image/png', 'image/jpeg', 'application/json', 'video/mp4', 'application/octet-stream']
WHERE id = 'scans';
