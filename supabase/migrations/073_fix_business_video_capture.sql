-- Fix Business plan missing video capture settings
-- The Business plan was added in migration 067 but didn't include video capture columns

UPDATE subscription_plans SET
    has_video_capture = true,
    video_max_duration_seconds = 300,
    video_max_size_mb = 500
WHERE slug = 'business';

-- Verify the update
-- SELECT slug, has_video_capture, video_max_duration_seconds, video_max_size_mb
-- FROM subscription_plans WHERE slug = 'business';
