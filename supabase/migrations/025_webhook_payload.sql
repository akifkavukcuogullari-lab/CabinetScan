-- Migration: Add webhook_payload column to projects table
-- This stores the full JSON payload that was sent to the showroom's webhook

ALTER TABLE projects
ADD COLUMN webhook_payload JSONB DEFAULT NULL;

-- Add index for faster queries on projects with webhook data
CREATE INDEX idx_projects_has_webhook ON projects ((webhook_payload IS NOT NULL))
WHERE webhook_payload IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN projects.webhook_payload IS
'Stores the full JSON payload sent to the showroom webhook when the project was submitted';
