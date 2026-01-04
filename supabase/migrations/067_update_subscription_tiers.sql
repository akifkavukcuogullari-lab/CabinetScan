-- ============================================
-- NEXTLEAN SCAN - UPDATE SUBSCRIPTION TIERS
-- Migration: 067_update_subscription_tiers
-- Purpose: Implement new 4-tier pricing structure (Starter, Pro, Business, Enterprise)
-- ============================================

-- ============================================
-- ADD NEW COLUMNS TO subscription_plans TABLE
-- ============================================

-- Add product_limit column
ALTER TABLE subscription_plans
ADD COLUMN IF NOT EXISTS product_limit INT;

-- Add project_retention_days column (NULL = unlimited)
ALTER TABLE subscription_plans
ADD COLUMN IF NOT EXISTS project_retention_days INT;

-- Add has_product_selection feature flag
ALTER TABLE subscription_plans
ADD COLUMN IF NOT EXISTS has_product_selection BOOLEAN NOT NULL DEFAULT true;

-- Add has_email_to_customer feature flag
ALTER TABLE subscription_plans
ADD COLUMN IF NOT EXISTS has_email_to_customer BOOLEAN NOT NULL DEFAULT false;

-- Add has_photos_video feature flag (available for all plans)
ALTER TABLE subscription_plans
ADD COLUMN IF NOT EXISTS has_photos_video BOOLEAN NOT NULL DEFAULT true;

-- ============================================
-- UPDATE TRIAL PLAN (14 days, selected plan features)
-- ============================================

UPDATE subscription_plans
SET
  description = 'Try CabinetScan free for 14 days with your selected plan features',
  features = '["14-day free trial", "Full access to selected plan features", "No credit card required"]'::jsonb
WHERE slug = 'trial';

-- ============================================
-- RENAME BASIC TO STARTER AND UPDATE VALUES
-- ============================================

UPDATE subscription_plans
SET
  name = 'Starter',
  slug = 'starter',
  price_monthly = 49.00,
  price_yearly = 470.00,
  project_limit = 20,
  product_limit = NULL, -- No products for Starter
  storage_limit_gb = 5,
  team_member_limit = 1,
  project_retention_days = 30,
  has_product_selection = false,
  has_webhook_access = false,
  has_api_access = false,
  has_autocad_export = false,
  has_priority_support = false,
  has_crm_integration = false,
  has_ai_agent = false,
  has_custom_branding = true,
  has_email_to_customer = false,
  has_photos_video = true,
  features = '["20 projects/month", "3D room scanning", "Floor plans", "Photos & video", "5GB storage", "1 team member", "30-day project retention", "Email support"]'::jsonb,
  description = 'Scan-only plan for small showrooms',
  is_featured = false,
  stripe_price_id_monthly = 'price_1SlhKZQ2jEPrpm04dgDhIS42',
  stripe_price_id_yearly = 'price_1SlhL0Q2jEPrpm041tbLnLLw'
WHERE slug = 'basic';

-- ============================================
-- UPDATE PRO PLAN ($149/mo)
-- ============================================

UPDATE subscription_plans
SET
  price_monthly = 149.00,
  price_yearly = 1430.00,
  project_limit = 100,
  product_limit = 100,
  storage_limit_gb = 50,
  team_member_limit = 3,
  project_retention_days = 60,
  has_product_selection = true,
  has_webhook_access = false,
  has_api_access = false,
  has_autocad_export = true,
  has_priority_support = true,
  has_crm_integration = false,
  has_ai_agent = false,
  has_custom_branding = true,
  has_email_to_customer = false,
  has_photos_video = true,
  features = '["100 projects/month", "100 products", "Product selection", "AutoCAD export", "50GB storage", "3 team members", "60-day project retention", "Priority support", "Photos & video"]'::jsonb,
  description = 'For growing showrooms with product catalogs',
  is_featured = true,
  stripe_price_id_monthly = 'price_1SlhLaQ2jEPrpm04QEaXwjeS',
  stripe_price_id_yearly = 'price_1SlhMJQ2jEPrpm04W2hbDzHY'
WHERE slug = 'pro';

-- ============================================
-- INSERT NEW BUSINESS PLAN ($299/mo)
-- ============================================

INSERT INTO subscription_plans (
  name, slug, price_monthly, price_yearly,
  stripe_price_id_monthly, stripe_price_id_yearly,
  project_limit, product_limit, storage_limit_gb, team_member_limit,
  project_retention_days, has_product_selection,
  has_webhook_access, has_api_access, has_autocad_export, has_priority_support,
  has_crm_integration, has_ai_agent, has_custom_branding,
  has_email_to_customer, has_photos_video,
  features, display_order, is_featured, is_active, description
)
VALUES (
  'Business',
  'business',
  299.00,
  2870.00,
  'price_1SlhS4Q2jEPrpm04SobNUMCa', -- Monthly Stripe price
  'price_1SlhT8Q2jEPrpm04jcbIQNOS', -- Yearly Stripe price
  NULL, -- Unlimited projects
  300,
  100,
  10,
  90, -- 90 day retention
  true,
  true, -- Webhooks
  true, -- API
  true, -- AutoCAD
  true, -- Priority support
  false, -- No CRM (Enterprise only)
  true, -- AI quotes
  true, -- Custom branding
  true, -- Email to customer
  true, -- Photos & video
  '["Unlimited projects", "300 products", "API & Webhooks", "AI-generated quotes", "Email to customer", "100GB storage", "10 team members", "90-day project retention", "Priority support", "AutoCAD export"]'::jsonb,
  3, -- Display after Pro
  false,
  true,
  'For power users with automation needs'
)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  price_monthly = EXCLUDED.price_monthly,
  price_yearly = EXCLUDED.price_yearly,
  stripe_price_id_monthly = EXCLUDED.stripe_price_id_monthly,
  stripe_price_id_yearly = EXCLUDED.stripe_price_id_yearly,
  project_limit = EXCLUDED.project_limit,
  product_limit = EXCLUDED.product_limit,
  storage_limit_gb = EXCLUDED.storage_limit_gb,
  team_member_limit = EXCLUDED.team_member_limit,
  project_retention_days = EXCLUDED.project_retention_days,
  has_product_selection = EXCLUDED.has_product_selection,
  has_webhook_access = EXCLUDED.has_webhook_access,
  has_api_access = EXCLUDED.has_api_access,
  has_autocad_export = EXCLUDED.has_autocad_export,
  has_priority_support = EXCLUDED.has_priority_support,
  has_crm_integration = EXCLUDED.has_crm_integration,
  has_ai_agent = EXCLUDED.has_ai_agent,
  has_custom_branding = EXCLUDED.has_custom_branding,
  has_email_to_customer = EXCLUDED.has_email_to_customer,
  has_photos_video = EXCLUDED.has_photos_video,
  features = EXCLUDED.features,
  display_order = EXCLUDED.display_order,
  is_featured = EXCLUDED.is_featured,
  is_active = EXCLUDED.is_active,
  description = EXCLUDED.description;

-- ============================================
-- UPDATE ENTERPRISE PLAN
-- ============================================

UPDATE subscription_plans
SET
  project_limit = NULL, -- Unlimited
  product_limit = NULL, -- Unlimited
  storage_limit_gb = NULL, -- Unlimited
  team_member_limit = NULL, -- Unlimited
  project_retention_days = NULL, -- Never archived
  has_product_selection = true,
  has_webhook_access = true,
  has_api_access = true,
  has_autocad_export = true,
  has_priority_support = true,
  has_crm_integration = true,
  has_ai_agent = true,
  has_custom_branding = true,
  has_email_to_customer = true,
  has_photos_video = true,
  features = '["Unlimited everything", "CRM integration", "AI-powered insights", "Dedicated account manager", "Custom onboarding", "SLA guarantee", "Never-archived projects"]'::jsonb,
  display_order = 4,
  description = 'Custom solutions for large enterprises'
WHERE slug = 'enterprise';

-- ============================================
-- UPDATE DISPLAY ORDER
-- ============================================

UPDATE subscription_plans SET display_order = 0 WHERE slug = 'trial';
UPDATE subscription_plans SET display_order = 1 WHERE slug = 'starter';
UPDATE subscription_plans SET display_order = 2 WHERE slug = 'pro';
UPDATE subscription_plans SET display_order = 3 WHERE slug = 'business';
UPDATE subscription_plans SET display_order = 4 WHERE slug = 'enterprise';

-- ============================================
-- UPDATE SHOWROOMS TABLE FOR TRIAL DURATION
-- ============================================

-- Update default trial duration to 14 days for new signups
-- (existing trial users keep their current trial_ends_at)

COMMENT ON COLUMN showrooms.trial_ends_at IS 'Trial end date - 14 days from signup for new users';

-- ============================================
-- UPDATE ARCHIVAL FUNCTION FOR TIER-BASED RETENTION
-- ============================================

CREATE OR REPLACE FUNCTION archive_old_project_files()
RETURNS INTEGER AS $$
DECLARE
  archived_count INTEGER := 0;
BEGIN
  -- Mark projects for archival based on their showroom's plan retention days
  -- Only archive projects that have files (scan_file_url, preview_image_url, or video_url)
  UPDATE projects p
  SET
    storage_tier = 'archived',
    archived_at = NOW()
  FROM showrooms s
  JOIN subscription_plans sp ON s.subscription_plan_id = sp.id
  WHERE
    p.showroom_id = s.id
    AND p.storage_tier = 'hot'
    AND sp.project_retention_days IS NOT NULL -- NULL means never archive
    AND p.created_at < NOW() - (sp.project_retention_days || ' days')::INTERVAL
    AND (p.scan_file_url IS NOT NULL OR p.preview_image_url IS NOT NULL);

  GET DIAGNOSTICS archived_count = ROW_COUNT;

  -- Log the archival action
  RAISE NOTICE 'Archived % projects based on plan retention policies', archived_count;

  RETURN archived_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- ADD HELPER FUNCTION FOR PRODUCT LIMIT CHECK
-- ============================================

CREATE OR REPLACE FUNCTION check_product_limit(p_showroom_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_limit INT;
    v_current_count INT;
BEGIN
    -- Get plan product limit
    SELECT sp.product_limit INTO v_limit
    FROM showrooms s
    JOIN subscription_plans sp ON s.subscription_plan_id = sp.id
    WHERE s.id = p_showroom_id;

    -- NULL means unlimited
    IF v_limit IS NULL THEN
        RETURN true;
    END IF;

    -- Get current product count
    SELECT COUNT(*) INTO v_current_count
    FROM products
    WHERE showroom_id = p_showroom_id;

    RETURN v_current_count < v_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- UPDATE check_plan_feature FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION check_plan_feature(p_showroom_id UUID, p_feature TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_plan subscription_plans;
BEGIN
    SELECT sp.* INTO v_plan
    FROM showrooms s
    JOIN subscription_plans sp ON s.subscription_plan_id = sp.id
    WHERE s.id = p_showroom_id;

    IF v_plan.id IS NULL THEN
        RETURN false;
    END IF;

    CASE p_feature
        WHEN 'webhook_access' THEN RETURN v_plan.has_webhook_access;
        WHEN 'api_access' THEN RETURN v_plan.has_api_access;
        WHEN 'autocad_export' THEN RETURN v_plan.has_autocad_export;
        WHEN 'priority_support' THEN RETURN v_plan.has_priority_support;
        WHEN 'crm_integration' THEN RETURN v_plan.has_crm_integration;
        WHEN 'ai_agent' THEN RETURN v_plan.has_ai_agent;
        WHEN 'custom_branding' THEN RETURN v_plan.has_custom_branding;
        WHEN 'product_selection' THEN RETURN v_plan.has_product_selection;
        WHEN 'email_to_customer' THEN RETURN v_plan.has_email_to_customer;
        WHEN 'photos_video' THEN RETURN v_plan.has_photos_video;
        ELSE RETURN false;
    END CASE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON COLUMN subscription_plans.product_limit IS 'Maximum number of products. NULL = unlimited.';
COMMENT ON COLUMN subscription_plans.project_retention_days IS 'Days to keep projects before archival. NULL = never archive.';
COMMENT ON COLUMN subscription_plans.has_product_selection IS 'Whether plan allows product selection in scans.';
COMMENT ON COLUMN subscription_plans.has_email_to_customer IS 'Whether plan can send emails to customers.';
COMMENT ON COLUMN subscription_plans.has_photos_video IS 'Whether plan supports photos and video capture.';
