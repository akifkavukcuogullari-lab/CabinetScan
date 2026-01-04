-- ============================================
-- NEXTLEAN SCAN - REMOVE ON-PREMISE OPTION
-- Migration: 057_remove_onpremise_option
-- Purpose: Remove "On-premise option" from Enterprise plan features
-- ============================================

UPDATE subscription_plans
SET features = '["Unlimited everything", "White-label branding", "CRM integration", "AI processing agent", "Dedicated support", "Custom SLA"]'::jsonb
WHERE slug = 'enterprise';
