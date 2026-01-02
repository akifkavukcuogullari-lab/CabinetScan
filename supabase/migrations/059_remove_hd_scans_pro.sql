-- ============================================
-- NEXTLEAN SCAN - REMOVE HD SCANS FROM PRO PLAN
-- Migration: 059_remove_hd_scans_pro
-- Purpose: Remove HD scans feature from Pro plan
-- ============================================

UPDATE subscription_plans
SET features = '["Unlimited projects", "500 products", "100GB storage", "10 team members", "Priority support", "API & Webhooks", "AutoCAD export", "AI generated quotes", "Email to customer"]'::jsonb
WHERE slug = 'pro';
