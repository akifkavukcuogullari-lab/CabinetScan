-- ============================================
-- PROJECT CHAT
-- Migration: 103_project_chat
-- Purpose: Human-to-human chat system for project collaboration
--          between staff, designers, owners, and managers
-- ============================================

-- ============================================
-- TABLES
-- ============================================

-- Project Chat Conversations (one per project)
CREATE TABLE IF NOT EXISTS project_chat_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'active', -- active | archived
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT project_chat_conversations_project_unique UNIQUE (project_id)
);

-- Project Chat Messages
CREATE TABLE IF NOT EXISTS project_chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES project_chat_conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    sender_role TEXT NOT NULL, -- staff | designer | owner | manager
    sender_name TEXT NOT NULL,
    message_type TEXT NOT NULL DEFAULT 'text', -- text | image | voice | video | file
    content TEXT, -- nullable for media-only messages
    is_read BOOLEAN NOT NULL DEFAULT false,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Project Chat Attachments
CREATE TABLE IF NOT EXISTS project_chat_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES project_chat_messages(id) ON DELETE CASCADE,
    file_type TEXT NOT NULL, -- image | voice | video | file
    file_url TEXT NOT NULL,
    file_name TEXT,
    file_size_bytes BIGINT,
    duration_seconds DECIMAL, -- for voice/video
    thumbnail_url TEXT,
    mime_type TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- INDEXES
-- ============================================

-- Conversation lookup by project
CREATE INDEX IF NOT EXISTS idx_chat_conversations_project ON project_chat_conversations(project_id);
CREATE INDEX IF NOT EXISTS idx_chat_conversations_showroom ON project_chat_conversations(showroom_id);

-- Message lookup by conversation (chronological)
CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation ON project_chat_messages(conversation_id, created_at);

-- Messages by sender
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender ON project_chat_messages(sender_id);

-- Unread messages lookup
CREATE INDEX IF NOT EXISTS idx_chat_messages_unread ON project_chat_messages(conversation_id, is_read)
    WHERE is_read = false;

-- Attachments by message
CREATE INDEX IF NOT EXISTS idx_chat_attachments_message ON project_chat_attachments(message_id);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE project_chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_chat_attachments ENABLE ROW LEVEL SECURITY;

-- Conversations: SELECT and INSERT for users with showroom access
DROP POLICY IF EXISTS chat_conversations_select ON project_chat_conversations;
CREATE POLICY chat_conversations_select ON project_chat_conversations FOR SELECT
    USING (has_showroom_access(showroom_id));

DROP POLICY IF EXISTS chat_conversations_insert ON project_chat_conversations;
CREATE POLICY chat_conversations_insert ON project_chat_conversations FOR INSERT
    WITH CHECK (has_showroom_access(showroom_id));

-- Messages: SELECT, INSERT, UPDATE for users with showroom access
DROP POLICY IF EXISTS chat_messages_select ON project_chat_messages;
CREATE POLICY chat_messages_select ON project_chat_messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM project_chat_conversations c
            WHERE c.id = conversation_id
            AND has_showroom_access(c.showroom_id)
        )
    );

DROP POLICY IF EXISTS chat_messages_insert ON project_chat_messages;
CREATE POLICY chat_messages_insert ON project_chat_messages FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM project_chat_conversations c
            WHERE c.id = conversation_id
            AND has_showroom_access(c.showroom_id)
        )
    );

-- UPDATE for marking messages as read
DROP POLICY IF EXISTS chat_messages_update ON project_chat_messages;
CREATE POLICY chat_messages_update ON project_chat_messages FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM project_chat_conversations c
            WHERE c.id = conversation_id
            AND has_showroom_access(c.showroom_id)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM project_chat_conversations c
            WHERE c.id = conversation_id
            AND has_showroom_access(c.showroom_id)
        )
    );

-- Attachments: SELECT and INSERT for users with showroom access
DROP POLICY IF EXISTS chat_attachments_select ON project_chat_attachments;
CREATE POLICY chat_attachments_select ON project_chat_attachments FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM project_chat_messages m
            JOIN project_chat_conversations c ON c.id = m.conversation_id
            WHERE m.id = message_id
            AND has_showroom_access(c.showroom_id)
        )
    );

DROP POLICY IF EXISTS chat_attachments_insert ON project_chat_attachments;
CREATE POLICY chat_attachments_insert ON project_chat_attachments FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM project_chat_messages m
            JOIN project_chat_conversations c ON c.id = m.conversation_id
            WHERE m.id = message_id
            AND has_showroom_access(c.showroom_id)
        )
    );

-- ============================================
-- TRIGGERS
-- ============================================

-- updated_at trigger for conversations
DROP TRIGGER IF EXISTS update_chat_conversations_updated_at ON project_chat_conversations;
CREATE TRIGGER update_chat_conversations_updated_at BEFORE UPDATE ON project_chat_conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
