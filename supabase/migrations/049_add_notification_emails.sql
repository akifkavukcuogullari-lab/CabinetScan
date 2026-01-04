-- ============================================
-- ADD NOTIFICATION EMAILS COLUMN
-- Allows showrooms to configure email addresses for project notifications
-- ============================================

ALTER TABLE showrooms
ADD COLUMN IF NOT EXISTS notification_emails TEXT;

COMMENT ON COLUMN showrooms.notification_emails IS
'Comma-separated email addresses (max 5) to notify when projects are submitted';
