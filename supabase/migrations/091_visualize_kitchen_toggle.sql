-- Add visualize_kitchen_enabled field to showrooms table
-- This controls whether the "Visualize Kitchen" button is visible for each showroom
-- Configurable by Super Admin, independent of subscription plan

ALTER TABLE showrooms
ADD COLUMN IF NOT EXISTS visualize_kitchen_enabled BOOLEAN DEFAULT false;

-- Add comment for documentation
COMMENT ON COLUMN showrooms.visualize_kitchen_enabled IS 'Controls visibility of Visualize Kitchen button. Set by Super Admin.';
