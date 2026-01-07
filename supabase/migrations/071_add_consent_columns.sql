-- Add consent tracking columns to projects table
-- This stores when and what terms the customer agreed to

ALTER TABLE projects
ADD COLUMN IF NOT EXISTS consent_agreed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS consent_terms_url TEXT,
ADD COLUMN IF NOT EXISTS consent_privacy_url TEXT;

-- Add comment for documentation
COMMENT ON COLUMN projects.consent_agreed_at IS 'Timestamp when customer agreed to terms and privacy policy';
COMMENT ON COLUMN projects.consent_terms_url IS 'URL of terms of service the customer agreed to';
COMMENT ON COLUMN projects.consent_privacy_url IS 'URL of privacy policy the customer agreed to';
