-- ============================================
-- NEXTLEAN SCAN - UPDATE ENTERPRISE FEATURES
-- Migration: 062_update_enterprise_features
-- Purpose: Remove White-label branding, add Everything in Pro
-- ============================================

UPDATE subscription_plans
SET features = '["Everything in Pro", "Unlimited everything", "CRM integration", "AI processing agent", "Dedicated support", "Custom SLA"]'::jsonb
WHERE slug = 'enterprise';
