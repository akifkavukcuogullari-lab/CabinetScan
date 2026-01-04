-- ============================================
-- NEXTLEAN SCAN - ADD AI FEATURES TO PRO PLAN
-- Migration: 058_add_pro_ai_features
-- Purpose: Add AI Quote and Email features to Pro plan
-- ============================================

UPDATE subscription_plans
SET features = '["Unlimited projects", "500 products", "100GB storage", "10 team members", "Priority support", "API & Webhooks", "AutoCAD export", "HD scans", "AI generated quotes", "Email to customer"]'::jsonb
WHERE slug = 'pro';
