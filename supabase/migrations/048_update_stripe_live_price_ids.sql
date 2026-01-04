-- ============================================
-- UPDATE STRIPE LIVE PRICE IDS - PRODUCTION
-- Updates subscription plans with live Stripe price IDs
-- ============================================

-- Update Basic plan
UPDATE subscription_plans
SET
  stripe_price_id_monthly = 'price_1SjtbGQ2jEPrpm04bBWFzaHH',
  stripe_price_id_yearly = NULL
WHERE slug = 'basic';

-- Update Pro plan
UPDATE subscription_plans
SET
  stripe_price_id_monthly = 'price_1SjtddQ2jEPrpm04vi8Xn7RY',
  stripe_price_id_yearly = NULL
WHERE slug = 'pro';

-- Verify the update
SELECT slug, name, stripe_price_id_monthly, stripe_price_id_yearly
FROM subscription_plans
WHERE slug IN ('basic', 'pro');
