-- ============================================
-- NEXTLEAN SCAN - ENHANCED SUBSCRIPTION LIMITS
-- Migration: 016_enhanced_subscription_limits
-- Purpose: Add product limits, scan quality, and other plan features
-- KEY CHANGE: Trial now gets FULL PRO features for 7 days
-- ============================================

-- Add new limit columns to subscription_plans
ALTER TABLE subscription_plans
ADD COLUMN IF NOT EXISTS product_limit INT,
ADD COLUMN IF NOT EXISTS scan_quality TEXT DEFAULT 'standard',
ADD COLUMN IF NOT EXISTS has_white_label BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS trial_duration_days INT DEFAULT 7,
ADD COLUMN IF NOT EXISTS grace_period_days INT DEFAULT 3,
ADD COLUMN IF NOT EXISTS soft_limit_threshold DECIMAL(3,2) DEFAULT 0.80;

-- Add comments for clarity
COMMENT ON COLUMN subscription_plans.product_limit IS 'Maximum number of products allowed. NULL = unlimited.';
COMMENT ON COLUMN subscription_plans.scan_quality IS 'Scan quality level: standard, hd, custom';
COMMENT ON COLUMN subscription_plans.has_white_label IS 'Whether white-label branding is available';
COMMENT ON COLUMN subscription_plans.trial_duration_days IS 'Default trial duration for this plan (7 days with full Pro features)';
COMMENT ON COLUMN subscription_plans.grace_period_days IS 'Grace period after payment failure';
COMMENT ON COLUMN subscription_plans.soft_limit_threshold IS 'Percentage at which to show warning (0.80 = 80%)';

-- Update Trial plan - NOW HAS FULL PRO FEATURES FOR 7 DAYS
-- Trial users get unlimited projects, 500 products, 100GB storage, webhooks, API, etc.
UPDATE subscription_plans SET
    product_limit = 500,                -- Same as Pro
    storage_limit_gb = 100,             -- Same as Pro
    project_limit = NULL,               -- Unlimited like Pro
    team_member_limit = 10,             -- Same as Pro
    trial_duration_days = 7,            -- 7-day trial (changed from 14)
    grace_period_days = 3,
    soft_limit_threshold = 0.90,        -- Same as Pro
    scan_quality = 'hd',                -- HD scans like Pro
    has_white_label = false,
    has_webhook_access = true,          -- Webhooks enabled
    has_api_access = true,              -- API access enabled
    has_autocad_export = true,          -- AutoCAD export enabled
    has_priority_support = true,        -- Priority support during trial
    features = '["7-day free trial with full Pro features", "Unlimited projects", "500 products", "100GB storage", "10 team members", "Priority support", "API & Webhooks", "AutoCAD export", "HD scans"]'::jsonb
WHERE slug = 'trial';

-- Update Basic plan
UPDATE subscription_plans SET
    product_limit = 100,
    storage_limit_gb = 10,
    project_limit = 25,
    team_member_limit = 3,
    price_monthly = 99.00,
    price_yearly = 990.00,
    soft_limit_threshold = 0.80,
    scan_quality = 'standard',
    has_white_label = false,
    features = '["25 projects/month", "100 products", "10GB storage", "3 team members", "Email support", "Full branding"]'::jsonb
WHERE slug = 'basic';

-- Update Pro plan
UPDATE subscription_plans SET
    product_limit = 500,
    storage_limit_gb = 100,
    project_limit = NULL,
    team_member_limit = 10,
    price_monthly = 249.00,
    price_yearly = 2490.00,
    scan_quality = 'hd',
    has_white_label = false,
    soft_limit_threshold = 0.90,
    features = '["Unlimited projects", "500 products", "100GB storage", "10 team members", "Priority support", "API & Webhooks", "AutoCAD export", "HD scans"]'::jsonb
WHERE slug = 'pro';

-- Update Enterprise plan
UPDATE subscription_plans SET
    product_limit = NULL,
    storage_limit_gb = NULL,
    project_limit = NULL,
    team_member_limit = NULL,
    scan_quality = 'hd',
    has_white_label = true,
    soft_limit_threshold = 0.95,
    features = '["Unlimited everything", "White-label branding", "CRM integration", "AI processing agent", "Dedicated support", "Custom SLA", "On-premise option"]'::jsonb
WHERE slug = 'enterprise';
