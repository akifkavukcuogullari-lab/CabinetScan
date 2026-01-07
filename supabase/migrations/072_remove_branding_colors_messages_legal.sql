-- Remove colors, messages, and legal fields from showroom_branding
-- These features are not used in the app

ALTER TABLE showroom_branding
DROP COLUMN IF EXISTS primary_color,
DROP COLUMN IF EXISTS secondary_color,
DROP COLUMN IF EXISTS accent_color,
DROP COLUMN IF EXISTS background_color,
DROP COLUMN IF EXISTS text_color,
DROP COLUMN IF EXISTS welcome_message,
DROP COLUMN IF EXISTS thank_you_message,
DROP COLUMN IF EXISTS terms_url,
DROP COLUMN IF EXISTS privacy_url;

-- Add comment for documentation
COMMENT ON TABLE showroom_branding IS 'Showroom branding - only logos are supported';
