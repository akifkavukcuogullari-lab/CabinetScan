-- ============================================
-- UNIQUE CONSTRAINT ON SHOWROOM EMAIL
-- Prevents multiple showrooms with the same email address
-- ============================================

-- Add unique constraint to showrooms.email
ALTER TABLE showrooms
ADD CONSTRAINT showrooms_email_unique UNIQUE (email);

-- Also add unique constraint to showroom_users.email
-- (one email can only be associated with one showroom)
-- Note: This prevents the same person from being owner of multiple showrooms
-- If you want to allow this, remove this constraint
ALTER TABLE showroom_users
ADD CONSTRAINT showroom_users_email_unique UNIQUE (email);
