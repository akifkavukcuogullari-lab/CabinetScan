-- Migration: Add webhook_url to showrooms table
-- Allows showroom owners to receive project submission data via webhook

-- Add webhook_url column to showrooms table
ALTER TABLE showrooms
ADD COLUMN IF NOT EXISTS webhook_url TEXT;

-- Add comment explaining the column
COMMENT ON COLUMN showrooms.webhook_url IS
'Optional webhook URL to receive project submission data in JSON format. Called after each successful project submission.';
