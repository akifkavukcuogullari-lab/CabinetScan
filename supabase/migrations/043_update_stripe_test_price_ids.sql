-- Update subscription plans with Stripe TEST price IDs
-- Run this in QA environment only

-- Update Basic plan
UPDATE subscription_plans
SET
  stripe_price_id_monthly = 'price_1SjtbGQ2jEPrpm04bBWFzaHH',
  stripe_price_id_yearly = NULL  -- Not using yearly pricing
WHERE slug = 'basic';

-- Update Pro plan
UPDATE subscription_plans
SET
  stripe_price_id_monthly = 'price_1SjtddQ2jEPrpm04vi8Xn7RY',
  stripe_price_id_yearly = NULL  -- Not using yearly pricing
WHERE slug = 'pro';

-- Verify the update
SELECT slug, name, stripe_price_id_monthly, stripe_price_id_yearly
FROM subscription_plans
WHERE slug IN ('basic', 'pro');
