-- Update Business plan price from $299 to $249
-- Annual price: $249 * 12 * 0.8 = $2,390

UPDATE subscription_plans SET
    price_monthly = 249.00,
    price_yearly = 2390.00
WHERE slug = 'business';
