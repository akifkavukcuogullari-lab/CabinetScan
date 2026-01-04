-- ============================================
-- UPDATE STRIPE PRICE IDS - TEST MODE
-- Updates subscription plans with correct test mode price IDs
-- ============================================

-- Update Basic plan
UPDATE subscription_plans
SET
  stripe_price_id_monthly = 'price_1SjwLMQ2jEPrpm048fvfLu0p',
  stripe_price_id_yearly = NULL
WHERE slug = 'basic';

-- Update Pro plan
UPDATE subscription_plans
SET
  stripe_price_id_monthly = 'price_1SjwLbQ2jEPrpm04qNjYUgRp',
  stripe_price_id_yearly = NULL
WHERE slug = 'pro';

-- Verify the update
SELECT slug, name, stripe_price_id_monthly, stripe_price_id_yearly
FROM subscription_plans
WHERE slug IN ('basic', 'pro');
