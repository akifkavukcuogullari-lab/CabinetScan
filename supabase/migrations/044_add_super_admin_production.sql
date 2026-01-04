-- ============================================
-- ADD SUPER ADMIN FOR PRODUCTION
-- Run this migration ONLY on production database
-- ============================================

-- First, you need to create the auth user in Supabase Dashboard:
-- Production Supabase Dashboard → Authentication → Users → Invite user
-- Email: your-email@domain.com

-- After the user signs up and confirms email, run this SQL:
-- Replace 'your-email@domain.com' with the actual email

DO $$
DECLARE
    v_user_id UUID;
    v_email TEXT := 'akifkavukcuogullari@gmail.com'; -- CHANGE THIS TO YOUR EMAIL
BEGIN
    -- Get the user_id from auth.users table
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = v_email;

    -- Check if user exists
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User with email % not found in auth.users. Please create the user first in Supabase Dashboard → Authentication → Users', v_email;
    END IF;

    -- Insert into admins table (or update if already exists)
    INSERT INTO admins (user_id, email, full_name, is_active)
    VALUES (
        v_user_id,
        v_email,
        'Mehmet Akif Kavukcuogullari', -- CHANGE THIS TO YOUR NAME
        true
    )
    ON CONFLICT (user_id) DO UPDATE
    SET is_active = true,
        full_name = EXCLUDED.full_name,
        updated_at = NOW();

    RAISE NOTICE 'Super admin created successfully for %', v_email;
END $$;

-- Verify super admin was created
SELECT id, email, full_name, is_active, created_at
FROM admins
WHERE email = 'akifkavukcuogullari@gmail.com'; -- CHANGE THIS TO YOUR EMAIL
