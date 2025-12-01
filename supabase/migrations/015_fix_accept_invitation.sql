-- Fix ambiguous column reference in accept_invitation function
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
    v_showroom_id UUID;
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

    -- Store showroom_id to avoid ambiguity
    v_showroom_id := v_invitation.showroom_id;

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
        SELECT 1 FROM showroom_users su
        WHERE su.user_id = p_user_id AND su.showroom_id = v_showroom_id
    ) THEN
        -- Still mark invitation as accepted
        UPDATE showroom_invitations
        SET status = 'accepted',
            accepted_at = NOW(),
            accepted_by_user_id = p_user_id
        WHERE id = p_invitation_id;

        SELECT su.id INTO v_showroom_user_id FROM showroom_users su
        WHERE su.user_id = p_user_id AND su.showroom_id = v_showroom_id;

        RETURN QUERY SELECT TRUE, v_showroom_user_id, v_showroom_id, NULL::TEXT;
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
        v_showroom_id,
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

    RETURN QUERY SELECT TRUE, v_showroom_user_id, v_showroom_id, NULL::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
