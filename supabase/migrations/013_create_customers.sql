-- ============================================
-- NEXTLEAN SCAN - CUSTOMER MANAGEMENT SYSTEM
-- Migration: 013_create_customers
-- ============================================

-- ============================================
-- 1. CREATE CUSTOMER TYPE ENUM
-- ============================================

CREATE TYPE customer_type AS ENUM ('homeowner', 'contractor');

-- ============================================
-- 2. PHONE NORMALIZATION FUNCTION
-- ============================================

-- Normalize phone numbers to E.164 format for consistent matching
CREATE OR REPLACE FUNCTION normalize_phone(phone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    cleaned TEXT;
BEGIN
    -- Remove all non-numeric characters
    cleaned := regexp_replace(phone, '[^0-9]', '', 'g');

    -- Handle US numbers (10 digits -> +1 prefix)
    IF length(cleaned) = 10 THEN
        RETURN '+1' || cleaned;
    -- Already has country code (11 digits starting with 1)
    ELSIF length(cleaned) = 11 AND cleaned LIKE '1%' THEN
        RETURN '+' || cleaned;
    -- Return cleaned version for other cases
    ELSE
        RETURN cleaned;
    END IF;
END;
$$;

-- ============================================
-- 3. CREATE CUSTOMERS TABLE
-- ============================================

CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    -- Core identification (phone is unique per showroom)
    phone TEXT NOT NULL,
    phone_normalized TEXT NOT NULL,

    -- Customer details
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT,
    customer_type customer_type NOT NULL DEFAULT 'homeowner',

    -- Address (now required in iOS form)
    address_line1 TEXT,
    city TEXT,
    state TEXT,
    zip_code TEXT,

    -- Metadata
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Unique constraint: one phone per showroom
    CONSTRAINT customers_showroom_phone_unique UNIQUE (showroom_id, phone_normalized)
);

-- Comment on table
COMMENT ON TABLE customers IS 'Customers are identified by phone number, unique per showroom. Supports homeowner and contractor types.';

-- ============================================
-- 4. AUTO-NORMALIZE PHONE TRIGGER
-- ============================================

CREATE OR REPLACE FUNCTION customers_normalize_phone_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.phone_normalized := normalize_phone(NEW.phone);
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_customers_normalize_phone
    BEFORE INSERT OR UPDATE OF phone ON customers
    FOR EACH ROW
    EXECUTE FUNCTION customers_normalize_phone_trigger();

-- ============================================
-- 5. CUSTOMERS INDEXES
-- ============================================

CREATE INDEX idx_customers_showroom_id ON customers(showroom_id);
CREATE INDEX idx_customers_phone_normalized ON customers(showroom_id, phone_normalized);
CREATE INDEX idx_customers_customer_type ON customers(showroom_id, customer_type);
CREATE INDEX idx_customers_created_at ON customers(showroom_id, created_at DESC);
CREATE INDEX idx_customers_email ON customers(email) WHERE email IS NOT NULL;

-- Full-text search on name
CREATE INDEX idx_customers_name_search ON customers
    USING GIN (to_tsvector('english', first_name || ' ' || last_name));

-- ============================================
-- 6. MODIFY PROJECTS TABLE
-- ============================================

-- Add customer_id foreign key
ALTER TABLE projects
    ADD COLUMN customer_id UUID REFERENCES customers(id) ON DELETE SET NULL;

-- Add end-client fields for contractor projects
ALTER TABLE projects
    ADD COLUMN end_client_first_name TEXT,
    ADD COLUMN end_client_last_name TEXT,
    ADD COLUMN end_client_phone TEXT,
    ADD COLUMN end_client_email TEXT,
    ADD COLUMN end_client_address TEXT;

-- Index for customer lookup
CREATE INDEX idx_projects_customer_id ON projects(customer_id);

-- ============================================
-- 7. RLS POLICIES FOR CUSTOMERS
-- ============================================

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

-- Authenticated users with showroom access can view their customers
CREATE POLICY customers_select ON customers FOR SELECT
    USING (has_showroom_access(showroom_id));

-- Customers are created via Edge Function (service role)
CREATE POLICY customers_insert ON customers FOR INSERT
    WITH CHECK (true); -- Controlled by Edge Function

-- Showroom users can update their customers
CREATE POLICY customers_update ON customers FOR UPDATE
    USING (has_showroom_access(showroom_id))
    WITH CHECK (has_showroom_access(showroom_id));

-- Only super admins can delete customers (protect history)
CREATE POLICY customers_delete ON customers FOR DELETE
    USING (is_super_admin());

-- Anonymous access for Edge Function find-or-create logic
CREATE POLICY customers_anon_select ON customers FOR SELECT TO anon
    USING (true); -- Edge Function needs to look up by phone

-- ============================================
-- 8. DATA MIGRATION - CREATE CUSTOMERS FROM EXISTING PROJECTS
-- ============================================

-- Create customers from existing projects that have phone numbers
INSERT INTO customers (
    showroom_id,
    phone,
    phone_normalized,
    first_name,
    last_name,
    email,
    customer_type,
    created_at
)
SELECT DISTINCT ON (p.showroom_id, normalize_phone(p.customer_phone))
    p.showroom_id,
    p.customer_phone,
    normalize_phone(p.customer_phone),
    p.customer_first_name,
    p.customer_last_name,
    p.customer_email,
    'homeowner'::customer_type,
    MIN(p.created_at) OVER (PARTITION BY p.showroom_id, normalize_phone(p.customer_phone))
FROM projects p
WHERE p.customer_phone IS NOT NULL
  AND p.customer_phone != ''
  AND length(regexp_replace(p.customer_phone, '[^0-9]', '', 'g')) >= 10
ORDER BY p.showroom_id, normalize_phone(p.customer_phone), p.created_at;

-- Link projects to newly created customers
UPDATE projects p
SET customer_id = c.id
FROM customers c
WHERE p.showroom_id = c.showroom_id
  AND normalize_phone(p.customer_phone) = c.phone_normalized
  AND p.customer_id IS NULL
  AND p.customer_phone IS NOT NULL
  AND p.customer_phone != '';

-- Create placeholder customers for projects without valid phone numbers
-- These will be marked as legacy and can be cleaned up later
-- Use ON CONFLICT to handle any edge cases
INSERT INTO customers (
    showroom_id,
    phone,
    phone_normalized,
    first_name,
    last_name,
    email,
    customer_type,
    notes,
    created_at
)
SELECT
    p.showroom_id,
    COALESCE(p.customer_email, 'LEGACY-' || p.id),
    'LEGACY-' || p.id,
    COALESCE(p.customer_first_name, 'Unknown'),
    COALESCE(p.customer_last_name, 'Customer'),
    p.customer_email,
    'homeowner'::customer_type,
    'Migrated from legacy project without valid phone number. Reference: ' || p.reference_number,
    p.created_at
FROM projects p
WHERE p.customer_id IS NULL
ON CONFLICT (showroom_id, phone_normalized) DO NOTHING;

-- Link these legacy projects
UPDATE projects p
SET customer_id = c.id
FROM customers c
WHERE c.phone_normalized = 'LEGACY-' || p.id
  AND p.customer_id IS NULL;

-- ============================================
-- 9. VERIFICATION
-- ============================================

DO $$
DECLARE
    total_projects INTEGER;
    linked_projects INTEGER;
    orphan_projects INTEGER;
    total_customers INTEGER;
    legacy_customers INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_projects FROM projects;
    SELECT COUNT(*) INTO linked_projects FROM projects WHERE customer_id IS NOT NULL;
    SELECT COUNT(*) INTO orphan_projects FROM projects WHERE customer_id IS NULL;
    SELECT COUNT(*) INTO total_customers FROM customers;
    SELECT COUNT(*) INTO legacy_customers FROM customers WHERE phone_normalized LIKE 'LEGACY-%';

    RAISE NOTICE 'Migration Summary:';
    RAISE NOTICE '  Total projects: %', total_projects;
    RAISE NOTICE '  Linked projects: %', linked_projects;
    RAISE NOTICE '  Orphan projects: %', orphan_projects;
    RAISE NOTICE '  Total customers: %', total_customers;
    RAISE NOTICE '  Legacy customers (no phone): %', legacy_customers;

    IF orphan_projects > 0 THEN
        RAISE WARNING 'Migration incomplete: % projects without customers', orphan_projects;
    ELSE
        RAISE NOTICE 'Migration complete: All projects linked to customers';
    END IF;
END $$;

-- ============================================
-- 10. HELPER FUNCTIONS
-- ============================================

-- Get customer statistics for a showroom
CREATE OR REPLACE FUNCTION get_customer_stats(p_showroom_id UUID)
RETURNS TABLE (
    total_customers BIGINT,
    homeowner_count BIGINT,
    contractor_count BIGINT,
    customers_this_month BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT COUNT(*) FROM customers WHERE showroom_id = p_showroom_id)::BIGINT,
        (SELECT COUNT(*) FROM customers WHERE showroom_id = p_showroom_id AND customer_type = 'homeowner')::BIGINT,
        (SELECT COUNT(*) FROM customers WHERE showroom_id = p_showroom_id AND customer_type = 'contractor')::BIGINT,
        (SELECT COUNT(*) FROM customers WHERE showroom_id = p_showroom_id AND created_at >= date_trunc('month', CURRENT_DATE))::BIGINT;
END;
$$;
