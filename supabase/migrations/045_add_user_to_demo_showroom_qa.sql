-- ============================================
-- ADD USER TO DEMO SHOWROOM - QA ONLY
-- Links makifkav44@gmail.com to Demo Showroom (ASD000)
-- ============================================

DO $$
DECLARE
    v_user_id UUID;
    v_showroom_id UUID := 'dc808235-f00d-45ee-b3e3-9b720d2c6926';
BEGIN
    -- Get user_id for makifkav44@gmail.com
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = 'makifkav44@gmail.com';

    -- Skip if user doesn't exist (e.g., running on production)
    IF v_user_id IS NULL THEN
        RAISE NOTICE 'User makifkav44@gmail.com not found - skipping (QA-only migration)';
        RETURN;
    END IF;

    -- Insert into showroom_users (or update if exists)
    INSERT INTO showroom_users (showroom_id, user_id, email, full_name, role, is_active, is_primary)
    VALUES (v_showroom_id, v_user_id, 'makifkav44@gmail.com', 'John Smith', 'owner', true, true)
    ON CONFLICT (showroom_id, user_id) DO UPDATE
    SET is_active = true,
        role = 'owner',
        is_primary = true,
        updated_at = NOW();

    RAISE NOTICE 'User makifkav44@gmail.com added to Demo Showroom successfully';
END $$;

-- Verify
SELECT
    su.id,
    u.email,
    s.name as showroom_name,
    s.showroom_code,
    su.role,
    su.is_active
FROM showroom_users su
JOIN auth.users u ON u.id = su.user_id
JOIN showrooms s ON s.id = su.showroom_id
WHERE u.email = 'makifkav44@gmail.com';
