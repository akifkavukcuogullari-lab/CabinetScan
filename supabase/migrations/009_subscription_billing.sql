-- ============================================
-- NEXTLYN SCAN - SUBSCRIPTION BILLING SYSTEM
-- Migration: 009_subscription_billing
-- ============================================

-- ============================================
-- SUBSCRIPTION PLANS TABLE
-- ============================================

CREATE TABLE subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    slug TEXT NOT NULL UNIQUE, -- 'free', 'basic', 'pro', 'enterprise'

    -- Pricing
    price_monthly DECIMAL(10,2) NOT NULL,
    price_yearly DECIMAL(10,2), -- Optional annual pricing (typically 10-20% discount)

    -- Stripe IDs (to be filled when Stripe is configured)
    stripe_price_id_monthly TEXT,
    stripe_price_id_yearly TEXT,
    stripe_product_id TEXT,

    -- Limits
    project_limit INT, -- NULL = unlimited
    storage_limit_gb INT DEFAULT 5,
    team_member_limit INT DEFAULT 1,

    -- Features (as JSONB for flexibility)
    features JSONB NOT NULL DEFAULT '[]',

    -- Pro Features
    has_webhook_access BOOLEAN NOT NULL DEFAULT false,
    has_api_access BOOLEAN NOT NULL DEFAULT false,
    has_autocad_export BOOLEAN NOT NULL DEFAULT false,
    has_priority_support BOOLEAN NOT NULL DEFAULT false,

    -- Enterprise Features
    has_crm_integration BOOLEAN NOT NULL DEFAULT false,
    has_ai_agent BOOLEAN NOT NULL DEFAULT false,
    has_custom_branding BOOLEAN NOT NULL DEFAULT true,

    -- Display
    display_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_featured BOOLEAN NOT NULL DEFAULT false,

    -- Metadata
    description TEXT,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- EXTENDED SUBSCRIPTION DETAILS
-- ============================================

-- Add more detailed subscription tracking to showrooms
ALTER TABLE showrooms
ADD COLUMN IF NOT EXISTS subscription_plan_id UUID REFERENCES subscription_plans(id),
ADD COLUMN IF NOT EXISTS stripe_subscription_id TEXT,
ADD COLUMN IF NOT EXISTS current_period_start TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS current_period_end TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS cancel_at_period_end BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS canceled_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS project_count_this_period INT DEFAULT 0;

-- ============================================
-- INVOICES TABLE
-- ============================================

CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    -- Stripe Reference
    stripe_invoice_id TEXT UNIQUE,
    stripe_payment_intent_id TEXT,

    -- Invoice Details
    invoice_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft', -- draft, open, paid, void, uncollectible

    -- Amounts (in cents for precision)
    subtotal_cents INT NOT NULL,
    tax_cents INT DEFAULT 0,
    total_cents INT NOT NULL,
    amount_paid_cents INT DEFAULT 0,
    amount_due_cents INT NOT NULL,

    currency TEXT NOT NULL DEFAULT 'usd',

    -- Period
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,

    -- Dates
    due_date TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,

    -- PDF
    invoice_pdf_url TEXT,
    hosted_invoice_url TEXT,

    -- Line Items
    line_items JSONB DEFAULT '[]',

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- API KEYS TABLE (Pro Feature)
-- ============================================

CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    name TEXT NOT NULL, -- User-friendly name for the key
    key_prefix TEXT NOT NULL, -- First 8 chars for identification (e.g., "nxs_live_")
    key_hash TEXT NOT NULL, -- SHA-256 hash of the full key

    -- Permissions
    scopes TEXT[] NOT NULL DEFAULT ARRAY['read:projects'], -- read:projects, write:projects, etc.

    -- Usage Tracking
    last_used_at TIMESTAMPTZ,
    request_count INT DEFAULT 0,

    -- Expiration
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT true,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES showroom_users(id),
    revoked_at TIMESTAMPTZ,
    revoked_by UUID REFERENCES showroom_users(id)
);

-- ============================================
-- WEBHOOK ENDPOINTS TABLE (Pro Feature)
-- ============================================

CREATE TABLE webhook_endpoints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    url TEXT NOT NULL,
    description TEXT,

    -- Events to subscribe to
    events TEXT[] NOT NULL DEFAULT ARRAY['project.submitted'],
    -- Available events: project.submitted, project.updated, project.status_changed

    -- Security
    secret TEXT NOT NULL, -- For HMAC signature verification

    -- Status
    is_active BOOLEAN NOT NULL DEFAULT true,

    -- Health Tracking
    last_delivery_at TIMESTAMPTZ,
    last_delivery_status TEXT, -- 'success', 'failed'
    consecutive_failures INT DEFAULT 0,
    disabled_at TIMESTAMPTZ, -- Auto-disabled after too many failures

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES showroom_users(id)
);

-- ============================================
-- WEBHOOK DELIVERIES TABLE (Pro Feature)
-- ============================================

CREATE TABLE webhook_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    webhook_endpoint_id UUID NOT NULL REFERENCES webhook_endpoints(id) ON DELETE CASCADE,

    -- Event Info
    event_type TEXT NOT NULL,
    event_id UUID NOT NULL, -- Reference to the triggering record

    -- Request
    request_payload JSONB NOT NULL,
    request_headers JSONB,

    -- Response
    response_status_code INT,
    response_body TEXT,
    response_headers JSONB,

    -- Timing
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    duration_ms INT,

    -- Status
    status TEXT NOT NULL DEFAULT 'pending', -- pending, success, failed
    error_message TEXT,

    -- Retry Info
    attempt_number INT NOT NULL DEFAULT 1,
    next_retry_at TIMESTAMPTZ
);

-- ============================================
-- SUBSCRIPTION HISTORY TABLE
-- ============================================

CREATE TABLE subscription_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    -- What changed
    event_type TEXT NOT NULL, -- 'created', 'upgraded', 'downgraded', 'canceled', 'reactivated', 'payment_failed'

    -- Plan Info
    from_plan_id UUID REFERENCES subscription_plans(id),
    to_plan_id UUID REFERENCES subscription_plans(id),

    -- Details
    details JSONB,
    stripe_event_id TEXT,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX idx_subscription_plans_slug ON subscription_plans(slug) WHERE is_active = true;
CREATE INDEX idx_invoices_showroom ON invoices(showroom_id);
CREATE INDEX idx_invoices_status ON invoices(showroom_id, status);
CREATE INDEX idx_invoices_stripe ON invoices(stripe_invoice_id);
CREATE INDEX idx_api_keys_showroom ON api_keys(showroom_id) WHERE is_active = true;
CREATE INDEX idx_api_keys_prefix ON api_keys(key_prefix);
CREATE INDEX idx_webhook_endpoints_showroom ON webhook_endpoints(showroom_id) WHERE is_active = true;
CREATE INDEX idx_webhook_deliveries_endpoint ON webhook_deliveries(webhook_endpoint_id);
CREATE INDEX idx_webhook_deliveries_status ON webhook_deliveries(status, next_retry_at) WHERE status = 'failed';
CREATE INDEX idx_subscription_history_showroom ON subscription_history(showroom_id);

-- ============================================
-- TRIGGERS
-- ============================================

CREATE TRIGGER update_subscription_plans_updated_at BEFORE UPDATE ON subscription_plans
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_invoices_updated_at BEFORE UPDATE ON invoices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_webhook_endpoints_updated_at BEFORE UPDATE ON webhook_endpoints
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_endpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_history ENABLE ROW LEVEL SECURITY;

-- Subscription Plans: Anyone can read active plans, only super admin can modify
CREATE POLICY "Anyone can view active subscription plans"
    ON subscription_plans FOR SELECT
    USING (is_active = true);

CREATE POLICY "Super admins can manage subscription plans"
    ON subscription_plans FOR ALL
    USING (is_super_admin());

-- Invoices: Showroom owners can view their own
CREATE POLICY "Showroom users can view their invoices"
    ON invoices FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY "Super admins can manage all invoices"
    ON invoices FOR ALL
    USING (is_super_admin());

-- API Keys: Showroom owners manage their own
CREATE POLICY "Showroom users can view their API keys"
    ON api_keys FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY "Showroom users can manage their API keys"
    ON api_keys FOR ALL
    USING (has_showroom_access(showroom_id));

CREATE POLICY "Super admins can manage all API keys"
    ON api_keys FOR ALL
    USING (is_super_admin());

-- Webhook Endpoints: Showroom owners manage their own
CREATE POLICY "Showroom users can view their webhook endpoints"
    ON webhook_endpoints FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY "Showroom users can manage their webhook endpoints"
    ON webhook_endpoints FOR ALL
    USING (has_showroom_access(showroom_id));

CREATE POLICY "Super admins can manage all webhook endpoints"
    ON webhook_endpoints FOR ALL
    USING (is_super_admin());

-- Webhook Deliveries: Read-only for showroom owners
CREATE POLICY "Showroom users can view their webhook deliveries"
    ON webhook_deliveries FOR SELECT
    USING (
        webhook_endpoint_id IN (
            SELECT id FROM webhook_endpoints WHERE has_showroom_access(showroom_id)
        )
    );

CREATE POLICY "Super admins can manage all webhook deliveries"
    ON webhook_deliveries FOR ALL
    USING (is_super_admin());

-- Subscription History: Read-only for showroom owners
CREATE POLICY "Showroom users can view their subscription history"
    ON subscription_history FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY "Super admins can manage all subscription history"
    ON subscription_history FOR ALL
    USING (is_super_admin());

-- ============================================
-- SEED SUBSCRIPTION PLANS
-- ============================================

INSERT INTO subscription_plans (
    name, slug, price_monthly, price_yearly, project_limit, storage_limit_gb, team_member_limit,
    has_webhook_access, has_api_access, has_autocad_export, has_priority_support,
    has_crm_integration, has_ai_agent, has_custom_branding,
    features, display_order, is_featured, description
) VALUES
(
    'Free Trial',
    'trial',
    0.00,
    0.00,
    5, -- 5 projects during trial
    1, -- 1GB storage
    1, -- 1 team member
    false, false, false, false,
    false, false, true,
    '["Up to 5 projects", "1GB storage", "Basic support", "7-day trial"]'::jsonb,
    0,
    false,
    'Try Nextlyn Scan free for 7 days'
),
(
    'Basic',
    'basic',
    100.00,
    1000.00, -- ~17% discount for annual
    20, -- 20 projects per month
    5, -- 5GB storage
    3, -- 3 team members
    false, false, false, false,
    false, false, true,
    '["20 projects/month", "5GB storage", "3 team members", "Email support", "Custom branding"]'::jsonb,
    1,
    false,
    'Perfect for small showrooms'
),
(
    'Pro',
    'pro',
    250.00,
    2500.00, -- ~17% discount for annual
    NULL, -- Unlimited projects
    50, -- 50GB storage
    10, -- 10 team members
    true, true, true, true,
    false, false, true,
    '["Unlimited projects", "50GB storage", "10 team members", "Priority support", "API & Webhooks", "AutoCAD export", "Custom branding"]'::jsonb,
    2,
    true, -- Featured plan
    'For growing showrooms'
),
(
    'Enterprise',
    'enterprise',
    0.00, -- Custom pricing
    0.00,
    NULL, -- Unlimited
    NULL, -- Unlimited (custom)
    NULL, -- Unlimited team members
    true, true, true, true,
    true, true, true,
    '["Unlimited everything", "CRM integration", "AI processing agent", "Dedicated support", "Custom SLA", "On-premise option"]'::jsonb,
    3,
    false,
    'Custom solutions for large enterprises'
);

-- ============================================
-- HELPER FUNCTION: Check Plan Features
-- ============================================

CREATE OR REPLACE FUNCTION check_plan_feature(p_showroom_id UUID, p_feature TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_plan subscription_plans;
BEGIN
    SELECT sp.* INTO v_plan
    FROM showrooms s
    JOIN subscription_plans sp ON s.subscription_plan_id = sp.id
    WHERE s.id = p_showroom_id;

    IF v_plan.id IS NULL THEN
        RETURN false;
    END IF;

    CASE p_feature
        WHEN 'webhook_access' THEN RETURN v_plan.has_webhook_access;
        WHEN 'api_access' THEN RETURN v_plan.has_api_access;
        WHEN 'autocad_export' THEN RETURN v_plan.has_autocad_export;
        WHEN 'priority_support' THEN RETURN v_plan.has_priority_support;
        WHEN 'crm_integration' THEN RETURN v_plan.has_crm_integration;
        WHEN 'ai_agent' THEN RETURN v_plan.has_ai_agent;
        WHEN 'custom_branding' THEN RETURN v_plan.has_custom_branding;
        ELSE RETURN false;
    END CASE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- HELPER FUNCTION: Check Project Limit
-- ============================================

CREATE OR REPLACE FUNCTION check_project_limit(p_showroom_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_limit INT;
    v_current_count INT;
BEGIN
    -- Get plan limit
    SELECT sp.project_limit INTO v_limit
    FROM showrooms s
    JOIN subscription_plans sp ON s.subscription_plan_id = sp.id
    WHERE s.id = p_showroom_id;

    -- NULL means unlimited
    IF v_limit IS NULL THEN
        RETURN true;
    END IF;

    -- Get current period project count
    SELECT project_count_this_period INTO v_current_count
    FROM showrooms
    WHERE id = p_showroom_id;

    RETURN COALESCE(v_current_count, 0) < v_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- TRIGGER: Increment Project Count
-- ============================================

CREATE OR REPLACE FUNCTION increment_project_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE showrooms
    SET project_count_this_period = COALESCE(project_count_this_period, 0) + 1
    WHERE id = NEW.showroom_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_increment_project_count
    AFTER INSERT ON projects
    FOR EACH ROW
    EXECUTE FUNCTION increment_project_count();

-- ============================================
-- FUNCTION: Generate Invoice Number
-- ============================================

CREATE OR REPLACE FUNCTION generate_invoice_number()
RETURNS TEXT AS $$
DECLARE
    v_year TEXT;
    v_sequence INT;
BEGIN
    v_year := to_char(NOW(), 'YYYY');

    -- Get next sequence number for this year
    SELECT COALESCE(MAX(
        CAST(SUBSTRING(invoice_number FROM 'INV-' || v_year || '-(\d+)') AS INT)
    ), 0) + 1
    INTO v_sequence
    FROM invoices
    WHERE invoice_number LIKE 'INV-' || v_year || '-%';

    RETURN 'INV-' || v_year || '-' || LPAD(v_sequence::TEXT, 5, '0');
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- FUNCTION: Generate API Key
-- ============================================

CREATE OR REPLACE FUNCTION generate_api_key_prefix(p_environment TEXT DEFAULT 'live')
RETURNS TEXT AS $$
BEGIN
    RETURN 'nxs_' || p_environment || '_';
END;
$$ LANGUAGE plpgsql;
