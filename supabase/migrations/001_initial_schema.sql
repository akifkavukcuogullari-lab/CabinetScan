-- ============================================
-- NEXTLEAN SCAN - INITIAL DATABASE SCHEMA
-- Migration: 001_initial_schema
-- ============================================

-- Note: uuid-ossp and pgcrypto are pre-enabled in Supabase
-- We use gen_random_uuid() which is built into PostgreSQL 13+

-- ============================================
-- ENUMS
-- ============================================

CREATE TYPE user_role AS ENUM ('super_admin', 'showroom_owner');
CREATE TYPE project_status AS ENUM ('draft', 'submitted', 'in_review', 'quoted', 'accepted', 'rejected', 'completed');
CREATE TYPE pricing_unit AS ENUM ('per_linear_ft', 'per_sq_ft', 'per_piece', 'per_cabinet', 'flat', 'none');
CREATE TYPE subscription_status AS ENUM ('trial', 'active', 'past_due', 'canceled', 'suspended');

-- ============================================
-- CORE TABLES
-- ============================================

-- Super Admin Users (Platform Owners)
CREATE TABLE admins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT admins_user_id_unique UNIQUE (user_id)
);

-- Master Product Categories (Super Admin Defined)
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    slug TEXT NOT NULL UNIQUE,
    description TEXT,
    pricing_unit pricing_unit NOT NULL DEFAULT 'none',
    display_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    icon_name TEXT, -- SF Symbol name for iOS
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Showrooms (Tenant Table)
CREATE TABLE showrooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE, -- URL-friendly identifier
    showroom_code TEXT NOT NULL UNIQUE, -- 6-char alphanumeric for customer entry

    -- Contact Information
    email TEXT NOT NULL,
    phone TEXT,
    address_line1 TEXT,
    address_line2 TEXT,
    city TEXT,
    state TEXT,
    postal_code TEXT,
    country TEXT DEFAULT 'US',

    -- Business Settings
    timezone TEXT NOT NULL DEFAULT 'America/New_York',
    currency TEXT NOT NULL DEFAULT 'USD',
    tax_rate DECIMAL(5,2) DEFAULT 0.00,

    -- Subscription & Billing
    subscription_status subscription_status NOT NULL DEFAULT 'trial',
    trial_ends_at TIMESTAMPTZ,
    subscription_plan TEXT,
    stripe_customer_id TEXT,

    -- Status
    is_active BOOLEAN NOT NULL DEFAULT true,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES admins(id)
);

-- Showroom Branding (One-to-One with Showrooms)
CREATE TABLE showroom_branding (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL UNIQUE REFERENCES showrooms(id) ON DELETE CASCADE,

    -- Logo
    logo_url TEXT,
    logo_dark_url TEXT, -- For dark mode

    -- Colors (Hex codes)
    primary_color TEXT DEFAULT '#2563EB',
    secondary_color TEXT DEFAULT '#1E40AF',
    accent_color TEXT DEFAULT '#3B82F6',
    background_color TEXT DEFAULT '#FFFFFF',
    text_color TEXT DEFAULT '#1F2937',

    -- Additional Branding
    welcome_message TEXT,
    thank_you_message TEXT,
    terms_url TEXT,
    privacy_url TEXT,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Showroom Users (Showroom Owner Logins)
CREATE TABLE showroom_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'owner', -- owner, manager, staff
    is_primary BOOLEAN NOT NULL DEFAULT false, -- Primary owner
    is_active BOOLEAN NOT NULL DEFAULT true,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    invited_by UUID REFERENCES showroom_users(id),

    CONSTRAINT showroom_users_user_showroom_unique UNIQUE (user_id, showroom_id)
);

-- Showroom Categories (Which categories each showroom has enabled)
CREATE TABLE showroom_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,

    is_enabled BOOLEAN NOT NULL DEFAULT true,
    display_order INT NOT NULL DEFAULT 0, -- Showroom-specific ordering
    custom_name TEXT, -- Override category name if desired
    is_required BOOLEAN NOT NULL DEFAULT false, -- Must customer select from this?

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT showroom_categories_unique UNIQUE (showroom_id, category_id)
);

-- Products (Per Showroom, Per Category)
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,

    name TEXT NOT NULL,
    description TEXT,
    sku TEXT, -- Optional internal reference

    -- Pricing
    price DECIMAL(10,2), -- NULL means "quote required"
    -- pricing_unit inherited from category

    -- Media
    image_url TEXT,
    thumbnail_url TEXT,
    additional_images TEXT[], -- Array of URLs

    -- Display
    display_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_featured BOOLEAN NOT NULL DEFAULT false,

    -- Metadata
    specifications JSONB DEFAULT '{}', -- Flexible key-value specs

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT products_showroom_sku_unique UNIQUE (showroom_id, sku)
);

-- ============================================
-- PROJECT / SUBMISSION TABLES
-- ============================================

-- Projects (Customer Submissions)
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE RESTRICT,

    -- Reference
    reference_number TEXT NOT NULL, -- Human-readable: "ABC123"

    -- Customer Info (not authenticated users)
    customer_first_name TEXT NOT NULL,
    customer_last_name TEXT NOT NULL,
    customer_email TEXT NOT NULL,
    customer_phone TEXT,

    -- Project Details
    project_name TEXT NOT NULL, -- e.g., "Kitchen Remodel"
    project_notes TEXT,

    -- Status Tracking
    status project_status NOT NULL DEFAULT 'submitted',
    submitted_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES showroom_users(id),

    -- Device Info (for debugging)
    device_model TEXT,
    ios_version TEXT,
    app_version TEXT,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT projects_reference_unique UNIQUE (showroom_id, reference_number)
);

-- Project Measurements (RoomPlan Data)
CREATE TABLE project_measurements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Room Identification
    room_name TEXT DEFAULT 'Main Room',
    room_type TEXT, -- kitchen, bathroom, etc.

    -- Raw RoomPlan Data
    roomplan_data JSONB NOT NULL, -- Full USDZ/JSON export

    -- Computed Summary (for quick display)
    total_linear_ft DECIMAL(10,2),
    total_sq_ft DECIMAL(10,2),
    wall_count INT,
    window_count INT,
    door_count INT,

    -- Individual Measurements
    measurements JSONB DEFAULT '{}', -- Parsed measurements

    -- Files
    usdz_file_url TEXT, -- 3D model file
    preview_image_url TEXT, -- 2D top-down preview

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Project Selections (Customer Product Choices)
CREATE TABLE project_selections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,

    -- Selection Details
    quantity INT DEFAULT 1,

    -- Snapshot of product at time of selection (prices change)
    product_name_snapshot TEXT NOT NULL,
    product_price_snapshot DECIMAL(10,2),
    pricing_unit_snapshot pricing_unit NOT NULL,

    -- Notes
    customer_notes TEXT,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT project_selections_unique UNIQUE (project_id, category_id)
);

-- ============================================
-- ACTIVITY / AUDIT TABLES
-- ============================================

-- Audit Log (Optional but recommended)
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    action TEXT NOT NULL, -- INSERT, UPDATE, DELETE
    old_values JSONB,
    new_values JSONB,
    performed_by UUID, -- Can be NULL for system actions
    performed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address INET,
    user_agent TEXT
);

-- ============================================
-- INDEXES
-- ============================================

-- Showrooms
CREATE INDEX idx_showrooms_code ON showrooms(showroom_code) WHERE is_active = true;
CREATE INDEX idx_showrooms_slug ON showrooms(slug) WHERE is_active = true;
CREATE INDEX idx_showrooms_subscription ON showrooms(subscription_status);

-- Showroom Users
CREATE INDEX idx_showroom_users_user_id ON showroom_users(user_id);
CREATE INDEX idx_showroom_users_showroom_id ON showroom_users(showroom_id) WHERE is_active = true;

-- Products
CREATE INDEX idx_products_showroom ON products(showroom_id) WHERE is_active = true;
CREATE INDEX idx_products_category ON products(showroom_id, category_id) WHERE is_active = true;
CREATE INDEX idx_products_display ON products(showroom_id, category_id, display_order) WHERE is_active = true;

-- Projects
CREATE INDEX idx_projects_showroom ON projects(showroom_id);
CREATE INDEX idx_projects_status ON projects(showroom_id, status);
CREATE INDEX idx_projects_submitted ON projects(showroom_id, submitted_at DESC);
CREATE INDEX idx_projects_customer_email ON projects(showroom_id, customer_email);

-- Showroom Categories
CREATE INDEX idx_showroom_categories_showroom ON showroom_categories(showroom_id) WHERE is_enabled = true;

-- Audit Log
CREATE INDEX idx_audit_log_table ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_performed_at ON audit_log(performed_at DESC);

-- ============================================
-- TRIGGERS FOR updated_at
-- ============================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to all tables with updated_at
CREATE TRIGGER update_admins_updated_at BEFORE UPDATE ON admins
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_categories_updated_at BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_showrooms_updated_at BEFORE UPDATE ON showrooms
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_showroom_branding_updated_at BEFORE UPDATE ON showroom_branding
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_showroom_users_updated_at BEFORE UPDATE ON showroom_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_showroom_categories_updated_at BEFORE UPDATE ON showroom_categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_projects_updated_at BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_project_measurements_updated_at BEFORE UPDATE ON project_measurements
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
