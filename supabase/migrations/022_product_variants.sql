-- ============================================
-- NEXTLEAN SCAN - PRODUCT VARIANTS (MODEL-SPECIFIC COLORS)
-- Migration: 022_product_variants
-- ============================================

-- Product Variants Table
-- Each cabinet model can have multiple color variants, each with its own price
CREATE TABLE product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,

    -- Variant Details
    name TEXT NOT NULL,  -- e.g., "White", "Navy Blue", "Natural Oak"
    color_code TEXT,     -- Hex color for swatch display, e.g., "#FFFFFF"

    -- Pricing (each variant can have its own price)
    price DECIMAL(10,2), -- NULL means "quote required"

    -- Media
    image_url TEXT,      -- Image showing product in this color
    thumbnail_url TEXT,

    -- Display
    display_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_default BOOLEAN NOT NULL DEFAULT false, -- Default variant shown first

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add has_variants flag to products table
-- When true, customer must select a variant; product price is ignored in favor of variant price
ALTER TABLE products ADD COLUMN has_variants BOOLEAN NOT NULL DEFAULT false;

-- Update project_selections to optionally reference a variant
ALTER TABLE project_selections ADD COLUMN variant_id UUID REFERENCES product_variants(id) ON DELETE RESTRICT;
ALTER TABLE project_selections ADD COLUMN variant_name_snapshot TEXT;

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX idx_product_variants_product ON product_variants(product_id) WHERE is_active = true;
CREATE INDEX idx_product_variants_display ON product_variants(product_id, display_order) WHERE is_active = true;
CREATE INDEX idx_products_has_variants ON products(showroom_id, category_id) WHERE has_variants = true AND is_active = true;

-- ============================================
-- TRIGGERS
-- ============================================

CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON product_variants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- RLS POLICIES
-- ============================================

ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;

-- Super admins can do anything
CREATE POLICY "Super admins have full access to product_variants"
    ON product_variants FOR ALL
    USING (is_super_admin())
    WITH CHECK (is_super_admin());

-- Showroom users can manage their variants via product relationship
CREATE POLICY "Showroom users can view their product variants"
    ON product_variants FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM products p
            JOIN showroom_users su ON su.showroom_id = p.showroom_id
            WHERE p.id = product_variants.product_id
            AND su.user_id = auth.uid()
            AND su.is_active = true
        )
    );

CREATE POLICY "Showroom users can insert their product variants"
    ON product_variants FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM products p
            JOIN showroom_users su ON su.showroom_id = p.showroom_id
            WHERE p.id = product_variants.product_id
            AND su.user_id = auth.uid()
            AND su.is_active = true
        )
    );

CREATE POLICY "Showroom users can update their product variants"
    ON product_variants FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM products p
            JOIN showroom_users su ON su.showroom_id = p.showroom_id
            WHERE p.id = product_variants.product_id
            AND su.user_id = auth.uid()
            AND su.is_active = true
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM products p
            JOIN showroom_users su ON su.showroom_id = p.showroom_id
            WHERE p.id = product_variants.product_id
            AND su.user_id = auth.uid()
            AND su.is_active = true
        )
    );

CREATE POLICY "Showroom users can delete their product variants"
    ON product_variants FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM products p
            JOIN showroom_users su ON su.showroom_id = p.showroom_id
            WHERE p.id = product_variants.product_id
            AND su.user_id = auth.uid()
            AND su.is_active = true
        )
    );

-- Anonymous users can view active variants for active products in active showrooms
CREATE POLICY "Anonymous users can view active product variants"
    ON product_variants FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM products p
            JOIN showrooms s ON s.id = p.showroom_id
            WHERE p.id = product_variants.product_id
            AND p.is_active = true
            AND s.is_active = true
        )
        AND is_active = true
    );

-- ============================================
-- REMOVE OLD CABINET COLOR CATEGORY
-- ============================================

-- We'll keep the Cabinet Color category for backwards compatibility
-- but showrooms using the new variant system won't need it
-- The category can be disabled per-showroom via showroom_categories

-- Add a comment to categories table documenting this change
COMMENT ON TABLE categories IS 'Master product categories. Note: Cabinet Color category is deprecated in favor of product_variants for cabinet models.';
