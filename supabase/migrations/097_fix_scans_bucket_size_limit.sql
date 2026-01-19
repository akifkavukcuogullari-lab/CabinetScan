-- ============================================
-- FIX SCANS BUCKET FILE SIZE LIMIT
-- Migration: 097_fix_scans_bucket_size_limit
-- Purpose: Increase file_size_limit from 500KB to 500MB for video uploads
-- ============================================

-- The scans bucket had file_size_limit set to 512000 (500KB) which is too small
-- for video files. Increase to 524288000 (500MB) to support video uploads.

UPDATE storage.buckets
SET file_size_limit = 524288000  -- 500MB
WHERE id = 'scans';
