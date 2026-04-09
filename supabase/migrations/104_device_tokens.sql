-- ============================================
-- DEVICE TOKENS FOR PUSH NOTIFICATIONS
-- Migration: 104_device_tokens
-- Purpose: Store push notification device tokens for staff app users
-- ============================================

-- ============================================
-- TABLE
-- ============================================

CREATE TABLE device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'ios', -- ios | android | web
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT device_tokens_user_token_unique UNIQUE (user_id, device_token)
);

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX idx_device_tokens_user ON device_tokens(user_id) WHERE is_active = true;

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

-- Users can only see their own tokens
CREATE POLICY device_tokens_select ON device_tokens FOR SELECT
    USING (auth.uid() = user_id);

-- Users can only insert their own tokens
CREATE POLICY device_tokens_insert ON device_tokens FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can only update their own tokens
CREATE POLICY device_tokens_update ON device_tokens FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can only delete their own tokens
CREATE POLICY device_tokens_delete ON device_tokens FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================
-- TRIGGERS
-- ============================================

CREATE TRIGGER update_device_tokens_updated_at BEFORE UPDATE ON device_tokens
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
