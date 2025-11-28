-- ============================================
-- NEXTLEAN SCAN - SHOWROOM INVITATIONS
-- Migration: 005_showroom_invitations
-- ============================================

-- ============================================
-- INVITATION STATUS ENUM
-- ============================================

CREATE TYPE invitation_status AS ENUM ('pending', 'accepted', 'expired', 'revoked');

-- ============================================
-- SHOWROOM INVITATIONS TABLE
-- ============================================

CREATE TABLE showroom_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    -- Invitee Information
    email TEXT NOT NULL,
    full_name TEXT,

    -- Invitation Status
    status invitation_status NOT NULL DEFAULT 'pending',

    -- Security Token (stored as SHA-256 hash)
    token_hash TEXT NOT NULL,

    -- Expiration
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),

    -- Tracking
    invited_by UUID NOT NULL REFERENCES auth.users(id),
    accepted_at TIMESTAMPTZ,
    accepted_by_user_id UUID REFERENCES auth.users(id),

    -- Metadata
    invitation_message TEXT, -- Optional custom message from admin
    role TEXT NOT NULL DEFAULT 'owner', -- owner, manager, staff

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- INDEXES
-- ============================================

-- Fast token lookup (primary lookup for invitation acceptance)
CREATE UNIQUE INDEX idx_invitations_token_hash ON showroom_invitations(token_hash);

-- Find pending invitations for a showroom
CREATE INDEX idx_invitations_showroom_status ON showroom_invitations(showroom_id, status);

-- Find pending invitations by email (check for duplicates)
CREATE INDEX idx_invitations_email_status ON showroom_invitations(email, status);

-- Cleanup expired invitations
CREATE INDEX idx_invitations_expires_at ON showroom_invitations(expires_at) WHERE status = 'pending';

-- ============================================
-- CONSTRAINTS
-- ============================================

-- Prevent duplicate pending invitations for same email and showroom
CREATE UNIQUE INDEX idx_invitations_pending_unique
ON showroom_invitations(showroom_id, email)
WHERE status = 'pending';

-- ============================================
-- TRIGGER FOR updated_at
-- ============================================

CREATE TRIGGER update_showroom_invitations_updated_at
BEFORE UPDATE ON showroom_invitations
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- ENHANCE SHOWROOM_USERS TABLE
-- ============================================

-- Add invitation tracking columns
ALTER TABLE showroom_users
ADD COLUMN invitation_id UUID REFERENCES showroom_invitations(id) ON DELETE SET NULL,
ADD COLUMN onboarding_completed_at TIMESTAMPTZ,
ADD COLUMN last_login_at TIMESTAMPTZ;

-- Index for tracking invitation to user conversion
CREATE INDEX idx_showroom_users_invitation ON showroom_users(invitation_id) WHERE invitation_id IS NOT NULL;

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Validate invitation token and return details
CREATE OR REPLACE FUNCTION validate_invitation_token(p_token_hash TEXT)
RETURNS TABLE (
    invitation_id UUID,
    showroom_id UUID,
    showroom_name TEXT,
    email TEXT,
    full_name TEXT,
    status invitation_status,
    expires_at TIMESTAMPTZ,
    is_valid BOOLEAN,
    validation_error TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        si.id AS invitation_id,
        si.showroom_id,
        s.name AS showroom_name,
        si.email,
        si.full_name,
        si.status,
        si.expires_at,
        CASE
            WHEN si.id IS NULL THEN FALSE
            WHEN si.status != 'pending' THEN FALSE
            WHEN si.expires_at < NOW() THEN FALSE
            ELSE TRUE
        END AS is_valid,
        CASE
            WHEN si.id IS NULL THEN 'Invitation not found'
            WHEN si.status = 'accepted' THEN 'Invitation has already been accepted'
            WHEN si.status = 'revoked' THEN 'Invitation has been revoked'
            WHEN si.status = 'expired' THEN 'Invitation has expired'
            WHEN si.expires_at < NOW() THEN 'Invitation has expired'
            ELSE NULL
        END AS validation_error
    FROM showroom_invitations si
    LEFT JOIN showrooms s ON s.id = si.showroom_id
    WHERE si.token_hash = p_token_hash
    LIMIT 1;

    -- If no rows returned, return a "not found" row
    IF NOT FOUND THEN
        RETURN QUERY SELECT
            NULL::UUID,
            NULL::UUID,
            NULL::TEXT,
            NULL::TEXT,
            NULL::TEXT,
            NULL::invitation_status,
            NULL::TIMESTAMPTZ,
            FALSE,
            'Invitation not found'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Accept invitation and create showroom_users entry
CREATE OR REPLACE FUNCTION accept_invitation(
    p_invitation_id UUID,
    p_user_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    showroom_user_id UUID,
    showroom_id UUID,
    error_message TEXT
) AS $$
DECLARE
    v_invitation showroom_invitations%ROWTYPE;
    v_showroom_user_id UUID;
BEGIN
    -- Get invitation details
    SELECT * INTO v_invitation
    FROM showroom_invitations
    WHERE id = p_invitation_id
    FOR UPDATE;

    -- Validate invitation exists
    IF v_invitation.id IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Invitation not found'::TEXT;
        RETURN;
    END IF;

    -- Validate invitation is pending
    IF v_invitation.status != 'pending' THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Invitation is no longer valid'::TEXT;
        RETURN;
    END IF;

    -- Validate not expired
    IF v_invitation.expires_at < NOW() THEN
        -- Update status to expired
        UPDATE showroom_invitations SET status = 'expired' WHERE id = p_invitation_id;
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Invitation has expired'::TEXT;
        RETURN;
    END IF;

    -- Check if user already has access to this showroom
    IF EXISTS (
        SELECT 1 FROM showroom_users
        WHERE user_id = p_user_id AND showroom_id = v_invitation.showroom_id
    ) THEN
        -- Still mark invitation as accepted
        UPDATE showroom_invitations
        SET status = 'accepted',
            accepted_at = NOW(),
            accepted_by_user_id = p_user_id
        WHERE id = p_invitation_id;

        SELECT id INTO v_showroom_user_id FROM showroom_users
        WHERE user_id = p_user_id AND showroom_id = v_invitation.showroom_id;

        RETURN QUERY SELECT TRUE, v_showroom_user_id, v_invitation.showroom_id, NULL::TEXT;
        RETURN;
    END IF;

    -- Create showroom_users entry
    INSERT INTO showroom_users (
        user_id,
        showroom_id,
        email,
        full_name,
        role,
        is_primary,
        is_active,
        invitation_id
    ) VALUES (
        p_user_id,
        v_invitation.showroom_id,
        v_invitation.email,
        COALESCE(v_invitation.full_name, ''),
        v_invitation.role,
        TRUE, -- First user from invitation is primary
        TRUE,
        p_invitation_id
    ) RETURNING id INTO v_showroom_user_id;

    -- Update invitation status
    UPDATE showroom_invitations
    SET status = 'accepted',
        accepted_at = NOW(),
        accepted_by_user_id = p_user_id
    WHERE id = p_invitation_id;

    RETURN QUERY SELECT TRUE, v_showroom_user_id, v_invitation.showroom_id, NULL::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- RLS POLICIES
-- ============================================

ALTER TABLE showroom_invitations ENABLE ROW LEVEL SECURITY;

-- Super admin full access
CREATE POLICY showroom_invitations_admin_all ON showroom_invitations
    FOR ALL
    USING (is_super_admin())
    WITH CHECK (is_super_admin());

-- Showroom owners can view invitations for their showrooms
CREATE POLICY showroom_invitations_owner_select ON showroom_invitations
    FOR SELECT
    USING (showroom_id IN (SELECT get_user_showroom_ids()));

-- Allow anon/authenticated users to validate tokens (via function, not direct access)
-- The validate_invitation_token function is SECURITY DEFINER so it bypasses RLS

-- ============================================
-- CRON JOB HELPER: Expire old invitations
-- ============================================

CREATE OR REPLACE FUNCTION expire_old_invitations()
RETURNS INTEGER AS $$
DECLARE
    expired_count INTEGER;
BEGIN
    WITH updated AS (
        UPDATE showroom_invitations
        SET status = 'expired', updated_at = NOW()
        WHERE status = 'pending' AND expires_at < NOW()
        RETURNING id
    )
    SELECT COUNT(*) INTO expired_count FROM updated;

    RETURN expired_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to service role for cron jobs
GRANT EXECUTE ON FUNCTION expire_old_invitations() TO service_role;
