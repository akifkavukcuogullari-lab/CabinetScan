-- ============================================
-- NEXTLEAN SCAN - REDUCE PRO TEAM MEMBERS TO 5
-- Migration: 060_pro_team_members_5
-- Purpose: Change Pro plan team members from 10 to 5
-- ============================================

UPDATE subscription_plans
SET
  features = '["Unlimited projects", "500 products", "100GB storage", "5 team members", "Priority support", "API & Webhooks", "AutoCAD export", "AI generated quotes", "Email to customer"]'::jsonb,
  team_member_limit = 5
WHERE slug = 'pro';
