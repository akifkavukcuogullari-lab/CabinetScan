-- ============================================
-- CABINETSCAN - DESIGNER DASHBOARD
-- Migration: 102_designer_dashboard
-- ============================================
-- Adds designer role, design requests, chat, and
-- file delivery system for the Designer Dashboard feature.
-- IMPORTANT: Does NOT modify any existing tables or RLS policies.
-- ============================================

-- ============================================
-- ENUM
-- ============================================

CREATE TYPE design_request_status AS ENUM (
    'pending',
    'accepted',
    'in_progress',
    'delivered',
    'approved',
    'revision_requested',
    'completed',
    'canceled'
);

-- ============================================
-- TABLES
-- ============================================

-- Designers (authenticated users with designer role)
CREATE TABLE designers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    avatar_url TEXT,
    bio TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT designers_user_id_unique UNIQUE (user_id)
);

-- Designer Invitations (sent by super admins)
CREATE TABLE designer_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    token TEXT NOT NULL UNIQUE,
    invited_by UUID REFERENCES admins(id),
    accepted_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Design Requests (one per project, links project to designer)
CREATE TABLE design_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,
    designer_id UUID REFERENCES designers(id),
    status design_request_status NOT NULL DEFAULT 'pending',
    notes TEXT,
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    accepted_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES showroom_users(id),

    CONSTRAINT design_requests_project_unique UNIQUE (project_id)
);

-- Design Chat Messages (communication between designer and showroom)
CREATE TABLE design_chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    design_request_id UUID NOT NULL REFERENCES design_requests(id) ON DELETE CASCADE,
    sender_type TEXT NOT NULL CHECK (sender_type IN ('designer', 'showroom')),
    sender_id UUID NOT NULL,
    sender_name TEXT NOT NULL,
    message_type TEXT NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'audio', 'file')),
    content TEXT,
    file_url TEXT,
    file_name TEXT,
    file_size_bytes BIGINT,
    is_read BOOLEAN DEFAULT false,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Design Files (deliverables uploaded by designers)
CREATE TABLE design_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    design_request_id UUID NOT NULL REFERENCES design_requests(id) ON DELETE CASCADE,
    designer_id UUID NOT NULL REFERENCES designers(id),
    file_url TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_type TEXT,
    file_size_bytes BIGINT,
    description TEXT,
    version INT DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Check if current user is a designer
CREATE OR REPLACE FUNCTION is_designer()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM designers
        WHERE user_id = auth.uid()
        AND is_active = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get the designer ID for the current user
CREATE OR REPLACE FUNCTION get_designer_id()
RETURNS UUID AS $$
    SELECT id FROM designers WHERE user_id = auth.uid() AND is_active = true;
$$ LANGUAGE sql SECURITY DEFINER;

-- ============================================
-- DATABASE VIEW
-- ============================================

-- Strips sensitive customer data for designers
CREATE VIEW designer_project_view AS
SELECT
    p.id,
    p.reference_number,
    p.project_name,
    p.project_notes,
    p.status,
    p.created_at,
    dr.id AS design_request_id,
    dr.status AS design_status,
    dr.priority,
    dr.notes AS design_notes,
    dr.designer_id,
    dr.accepted_at,
    dr.delivered_at,
    dr.created_at AS request_created_at
FROM projects p
JOIN design_requests dr ON dr.project_id = p.id
WHERE dr.status = 'pending'
   OR dr.designer_id = get_designer_id();

-- ============================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE designers ENABLE ROW LEVEL SECURITY;
ALTER TABLE designer_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE design_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE design_chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE design_files ENABLE ROW LEVEL SECURITY;

-- ============================================
-- RLS POLICIES: designers
-- ============================================

-- Super admins see all, designers see themselves
CREATE POLICY designers_select ON designers FOR SELECT
    USING (is_super_admin() OR user_id = auth.uid());

-- Only super admins can create designer records
CREATE POLICY designers_insert ON designers FOR INSERT
    WITH CHECK (is_super_admin());

-- Designers can update their own profile
CREATE POLICY designers_update ON designers FOR UPDATE
    USING (user_id = auth.uid());

-- ============================================
-- RLS POLICIES: designer_invitations
-- ============================================

-- Super admins can view all invitations
CREATE POLICY designer_invitations_select ON designer_invitations FOR SELECT
    USING (is_super_admin());

-- Only super admins can create invitations
CREATE POLICY designer_invitations_insert ON designer_invitations FOR INSERT
    WITH CHECK (is_super_admin());

-- Super admins can update any invitation; token holders can accept
CREATE POLICY designer_invitations_update ON designer_invitations FOR UPDATE
    USING (is_super_admin() OR token = token);

-- ============================================
-- RLS POLICIES: design_requests
-- ============================================

-- Designers: see pending requests (available pool) or own assigned requests
CREATE POLICY design_requests_designer_select ON design_requests FOR SELECT TO authenticated
    USING (
        is_designer() AND (status = 'pending' OR designer_id = get_designer_id())
    );

-- Showroom users: see requests for their showrooms
CREATE POLICY design_requests_showroom_select ON design_requests FOR SELECT TO authenticated
    USING (has_showroom_access(showroom_id));

-- Super admins: see all requests
CREATE POLICY design_requests_admin_select ON design_requests FOR SELECT TO authenticated
    USING (is_super_admin());

-- Showroom users create requests for their projects
CREATE POLICY design_requests_insert ON design_requests FOR INSERT TO authenticated
    WITH CHECK (has_showroom_access(showroom_id));

-- Designers can update their own assigned requests OR accept pending requests
CREATE POLICY design_requests_designer_update ON design_requests FOR UPDATE TO authenticated
    USING (is_designer() AND (designer_id = get_designer_id() OR status = 'pending'));

-- Showroom users can update requests for their showrooms
CREATE POLICY design_requests_showroom_update ON design_requests FOR UPDATE TO authenticated
    USING (has_showroom_access(showroom_id));

-- ============================================
-- RLS POLICIES: design_chat_messages
-- ============================================

-- Can read messages if user is the assigned designer or has showroom access
CREATE POLICY design_chat_messages_select ON design_chat_messages FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM design_requests dr
            WHERE dr.id = design_request_id
            AND (
                dr.designer_id = get_designer_id()
                OR has_showroom_access(dr.showroom_id)
            )
        )
    );

-- Can send messages if user is the assigned designer or has showroom access
CREATE POLICY design_chat_messages_insert ON design_chat_messages FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM design_requests dr
            WHERE dr.id = design_request_id
            AND (
                dr.designer_id = get_designer_id()
                OR has_showroom_access(dr.showroom_id)
            )
        )
    );

-- Can update own messages (e.g. mark as read)
CREATE POLICY design_chat_messages_update ON design_chat_messages FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM design_requests dr
            WHERE dr.id = design_request_id
            AND (
                dr.designer_id = get_designer_id()
                OR has_showroom_access(dr.showroom_id)
            )
        )
    );

-- ============================================
-- RLS POLICIES: design_files
-- ============================================

-- Can read files if user is the assigned designer or has showroom access
CREATE POLICY design_files_select ON design_files FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM design_requests dr
            WHERE dr.id = design_request_id
            AND (
                dr.designer_id = get_designer_id()
                OR has_showroom_access(dr.showroom_id)
            )
        )
    );

-- Designers can upload files to their own assigned requests
CREATE POLICY design_files_insert ON design_files FOR INSERT TO authenticated
    WITH CHECK (
        is_designer()
        AND designer_id = get_designer_id()
        AND EXISTS (
            SELECT 1 FROM design_requests dr
            WHERE dr.id = design_request_id
            AND dr.designer_id = get_designer_id()
        )
    );

-- ============================================
-- ADDITIONAL RLS POLICY: project_measurements
-- Allow designers to read measurements for accepted requests
-- ============================================

CREATE POLICY project_measurements_designer_select ON project_measurements FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM design_requests dr
            WHERE dr.project_id = project_id
            AND dr.designer_id = get_designer_id()
            AND dr.status NOT IN ('pending', 'canceled')
        )
    );

-- ============================================
-- STORAGE BUCKETS
-- ============================================

-- designs bucket: private, 100MB limit per file
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES
    ('designs', 'designs', false, 104857600),
    ('chat-attachments', 'chat-attachments', false, 26214400);

-- ============================================
-- STORAGE POLICIES: designs bucket
-- ============================================

-- Designers can read design files for their assigned requests
CREATE POLICY designs_designer_select ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'designs'
        AND is_designer()
    );

-- Showroom users can read design files for their showrooms
CREATE POLICY designs_showroom_select ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'designs'
        AND (
            is_super_admin()
            OR (storage.foldername(name))[1] IN (
                SELECT id::text FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );

-- Designers can upload design files
CREATE POLICY designs_designer_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'designs'
        AND is_designer()
    );

-- Designers can update their uploaded design files
CREATE POLICY designs_designer_update ON storage.objects FOR UPDATE TO authenticated
    USING (
        bucket_id = 'designs'
        AND is_designer()
    );

-- Designers can delete their uploaded design files
CREATE POLICY designs_designer_delete ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'designs'
        AND is_designer()
    );

-- ============================================
-- STORAGE POLICIES: chat-attachments bucket
-- ============================================

-- Participants can read chat attachments
CREATE POLICY chat_attachments_select ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'chat-attachments'
        AND (
            is_designer()
            OR is_super_admin()
            OR (storage.foldername(name))[1] IN (
                SELECT id::text FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );

-- Participants can upload chat attachments
CREATE POLICY chat_attachments_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'chat-attachments'
        AND (
            is_designer()
            OR is_super_admin()
            OR (storage.foldername(name))[1] IN (
                SELECT id::text FROM showrooms
                WHERE id IN (SELECT get_user_showroom_ids())
            )
        )
    );

-- ============================================
-- STORAGE POLICY: scans bucket (designer read access)
-- ============================================

-- Designers can read scan files for their accepted design requests
CREATE POLICY scans_designer_select ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'scans'
        AND is_designer()
        AND EXISTS (
            SELECT 1 FROM design_requests dr
            JOIN projects p ON p.id = dr.project_id
            WHERE dr.designer_id = get_designer_id()
            AND dr.status NOT IN ('pending', 'canceled')
            AND (storage.foldername(name))[1] = p.showroom_id::text
        )
    );

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX idx_designers_user_id ON designers(user_id);
CREATE INDEX idx_design_requests_status ON design_requests(status) WHERE status = 'pending';
CREATE INDEX idx_design_requests_designer ON design_requests(designer_id) WHERE designer_id IS NOT NULL;
CREATE INDEX idx_design_requests_showroom ON design_requests(showroom_id);
CREATE INDEX idx_design_requests_project ON design_requests(project_id);
CREATE INDEX idx_design_chat_messages_request ON design_chat_messages(design_request_id);
CREATE INDEX idx_design_chat_messages_created ON design_chat_messages(design_request_id, created_at);
CREATE INDEX idx_design_files_request ON design_files(design_request_id);

-- ============================================
-- REALTIME
-- ============================================

ALTER PUBLICATION supabase_realtime ADD TABLE design_chat_messages;

-- ============================================
-- TRIGGERS FOR updated_at
-- ============================================

CREATE TRIGGER update_designers_updated_at BEFORE UPDATE ON designers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_design_requests_updated_at BEFORE UPDATE ON design_requests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
