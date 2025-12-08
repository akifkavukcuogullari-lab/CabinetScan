-- ============================================
-- QUOTE EMAILS TABLE (Simplified)
-- Stores AI-generated quote emails from n8n for review before sending
-- ============================================

CREATE TABLE quote_emails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Email fields (editable by showroom owner)
    recipient_email TEXT NOT NULL,
    subject TEXT NOT NULL,
    body_html TEXT NOT NULL,
    body_text TEXT,

    -- Quote summary for display
    customer_name TEXT,
    reference_number TEXT,
    grand_total TEXT,
    quote_summary JSONB,  -- { cabinets, countertops, backsplash, total }

    -- Status: pending (from n8n) -> sent (approved and sent)
    status TEXT NOT NULL DEFAULT 'pending',
    sent_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for quick lookup
CREATE INDEX idx_quote_emails_project ON quote_emails(project_id);

-- Trigger for updated_at
CREATE TRIGGER update_quote_emails_updated_at
    BEFORE UPDATE ON quote_emails
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE quote_emails ENABLE ROW LEVEL SECURITY;

-- Showroom owners can view/update their project's quotes
CREATE POLICY quote_emails_select ON quote_emails FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id
            AND has_showroom_access(p.showroom_id)
        )
    );

-- Insert via Edge Function (anon for webhook)
CREATE POLICY quote_emails_insert ON quote_emails FOR INSERT
    WITH CHECK (true);

-- Update by showroom owners
CREATE POLICY quote_emails_update ON quote_emails FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id
            AND has_showroom_access(p.showroom_id)
        )
    );

-- ============================================
-- Add quote webhook URL to showrooms (for sending)
-- ============================================

ALTER TABLE showrooms
ADD COLUMN IF NOT EXISTS quote_webhook_url TEXT;
