-- Fix trial plan to have Pro-level limits
-- Trial users should experience Pro features to see the full value

UPDATE subscription_plans
SET
  project_limit = 100,
  product_limit = 100,
  storage_limit_gb = 50,
  team_member_limit = 3,
  project_retention_days = 60,
  has_product_selection = true,
  has_autocad_export = true,
  has_priority_support = true,
  has_custom_branding = true,
  has_photos_video = true,
  features = '["100 projects/month", "100 products", "Product selection", "AutoCAD export", "50GB storage", "3 team members", "60-day project retention", "Priority support", "Photos & video"]'::jsonb,
  description = '14-day free trial with Pro features'
WHERE slug = 'trial';
