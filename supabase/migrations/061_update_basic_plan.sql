-- ============================================
-- NEXTLEAN SCAN - UPDATE BASIC PLAN
-- Migration: 061_update_basic_plan
-- Purpose: Update Basic plan price to $149, team members to 2, projects to 40
-- ============================================

UPDATE subscription_plans
SET
  price_monthly = 149,
  team_member_limit = 2,
  project_limit = 40,
  features = '["40 projects/month", "50 products", "10GB storage", "2 team members", "Email support"]'::jsonb
WHERE slug = 'basic';
