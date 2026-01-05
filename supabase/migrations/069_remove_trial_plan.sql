-- Remove trial plan from subscription_plans
-- Trial users should use Pro plan features directly, not a separate trial plan

-- Deactivate trial plan (keep for reference but hide from UI)
UPDATE subscription_plans
SET is_active = false
WHERE slug = 'trial';
