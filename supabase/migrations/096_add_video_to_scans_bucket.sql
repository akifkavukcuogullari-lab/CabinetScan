-- ============================================
-- ADD VIDEO SUPPORT TO SCANS BUCKET
-- Migration: 096_add_video_to_scans_bucket
-- Purpose: Allow video/mp4 uploads for scan recordings
-- ============================================

-- Update the scans bucket to allow video/mp4 uploads
UPDATE storage.buckets
SET
    allowed_mime_types = ARRAY['model/vnd.usdz+zip', 'image/png', 'image/jpeg', 'application/json', 'video/mp4'],
    file_size_limit = 524288000  -- 500MB to accommodate video files
WHERE id = 'scans';

-- Add comment for documentation
COMMENT ON TABLE storage.buckets IS 'Storage buckets configuration - scans bucket updated to support video/mp4 for scan recordings';
