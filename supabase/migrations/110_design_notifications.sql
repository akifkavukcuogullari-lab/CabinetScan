-- Design notifications system
-- In-app notifications for designers and showroom users

CREATE TABLE design_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Who should see this notification
    recipient_type TEXT NOT NULL CHECK (recipient_type IN ('designer', 'showroom')),
    recipient_id UUID NOT NULL,  -- designer.id or showroom_users.user_id

    -- What happened
    event_type TEXT NOT NULL CHECK (event_type IN (
        'design_requested',        -- showroom created a request (notify all designers? no - pool is visible)
        'design_accepted',         -- designer accepted (notify showroom)
        'design_delivered',        -- designer delivered (notify showroom)
        'design_approved',         -- showroom approved (notify designer)
        'design_revision',         -- showroom requested revision (notify designer)
        'design_dropped',          -- designer dropped project (notify showroom)
        'design_completed',        -- showroom marked complete (notify designer)
        'design_canceled',         -- showroom canceled (notify designer)
        'chat_message',            -- new chat message (notify other party)
        'estimate_set'             -- designer set estimated completion (notify showroom)
    )),

    -- Context
    design_request_id UUID REFERENCES design_requests(id) ON DELETE CASCADE,
    project_reference TEXT,       -- denormalized for display
    message TEXT NOT NULL,        -- human-readable notification text

    -- Status
    is_read BOOLEAN DEFAULT false,
    read_at TIMESTAMPTZ,

    -- Whether email was sent for this notification
    email_sent BOOLEAN DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_design_notifications_recipient ON design_notifications(recipient_type, recipient_id, is_read);
CREATE INDEX idx_design_notifications_created ON design_notifications(recipient_id, created_at DESC);

-- RLS
ALTER TABLE design_notifications ENABLE ROW LEVEL SECURITY;

-- Users can only see their own notifications
CREATE POLICY design_notifications_select ON design_notifications FOR SELECT TO authenticated
    USING (
        (recipient_type = 'designer' AND recipient_id = get_designer_id())
        OR (recipient_type = 'showroom' AND recipient_id = auth.uid())
    );

-- Users can update (mark read) their own notifications
CREATE POLICY design_notifications_update ON design_notifications FOR UPDATE TO authenticated
    USING (
        (recipient_type = 'designer' AND recipient_id = get_designer_id())
        OR (recipient_type = 'showroom' AND recipient_id = auth.uid())
    );

-- System/functions can insert (no direct user insert)
CREATE POLICY design_notifications_insert ON design_notifications FOR INSERT TO authenticated
    WITH CHECK (true);

-- Enable realtime for instant notifications
ALTER PUBLICATION supabase_realtime ADD TABLE design_notifications;
