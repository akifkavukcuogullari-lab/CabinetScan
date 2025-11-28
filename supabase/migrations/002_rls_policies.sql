-- ============================================
-- NEXTLEAN SCAN - ROW LEVEL SECURITY POLICIES
-- Migration: 002_rls_policies
-- ============================================

-- Enable RLS on all tables
ALTER TABLE admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE showrooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE showroom_branding ENABLE ROW LEVEL SECURITY;
ALTER TABLE showroom_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE showroom_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_measurements ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_selections ENABLE ROW LEVEL SECURITY;

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Check if current user is a super admin
CREATE OR REPLACE FUNCTION is_super_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM admins
        WHERE user_id = auth.uid()
        AND is_active = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get showroom IDs the current user has access to
CREATE OR REPLACE FUNCTION get_user_showroom_ids()
RETURNS SETOF UUID AS $$
BEGIN
    RETURN QUERY
    SELECT showroom_id FROM showroom_users
    WHERE user_id = auth.uid()
    AND is_active = true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if user has access to specific showroom
CREATE OR REPLACE FUNCTION has_showroom_access(p_showroom_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN is_super_admin() OR EXISTS (
        SELECT 1 FROM showroom_users
        WHERE user_id = auth.uid()
        AND showroom_id = p_showroom_id
        AND is_active = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- ADMINS POLICIES
-- ============================================

-- Super admins can see all admins
CREATE POLICY admins_select ON admins FOR SELECT
    USING (is_super_admin() OR user_id = auth.uid());

-- Only existing super admins can create new admins
CREATE POLICY admins_insert ON admins FOR INSERT
    WITH CHECK (is_super_admin());

-- Admins can update their own profile, super admins can update any
CREATE POLICY admins_update ON admins FOR UPDATE
    USING (is_super_admin() OR user_id = auth.uid())
    WITH CHECK (is_super_admin() OR user_id = auth.uid());

-- ============================================
-- CATEGORIES POLICIES (Super Admin managed, public read)
-- ============================================

-- Anyone authenticated can read active categories
CREATE POLICY categories_select ON categories FOR SELECT
    USING (is_active = true OR is_super_admin());

-- Only super admins can manage categories
CREATE POLICY categories_insert ON categories FOR INSERT
    WITH CHECK (is_super_admin());

CREATE POLICY categories_update ON categories FOR UPDATE
    USING (is_super_admin())
    WITH CHECK (is_super_admin());

CREATE POLICY categories_delete ON categories FOR DELETE
    USING (is_super_admin());

-- ============================================
-- SHOWROOMS POLICIES
-- ============================================

-- Super admins see all, showroom users see their own
CREATE POLICY showrooms_select ON showrooms FOR SELECT
    USING (
        is_super_admin()
        OR id IN (SELECT get_user_showroom_ids())
    );

-- Only super admins can create showrooms
CREATE POLICY showrooms_insert ON showrooms FOR INSERT
    WITH CHECK (is_super_admin());

-- Super admins can update any, showroom owners their own
CREATE POLICY showrooms_update ON showrooms FOR UPDATE
    USING (has_showroom_access(id))
    WITH CHECK (has_showroom_access(id));

-- Only super admins can delete showrooms
CREATE POLICY showrooms_delete ON showrooms FOR DELETE
    USING (is_super_admin());

-- ============================================
-- SHOWROOM BRANDING POLICIES
-- ============================================

CREATE POLICY showroom_branding_select ON showroom_branding FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY showroom_branding_insert ON showroom_branding FOR INSERT
    WITH CHECK (has_showroom_access(showroom_id));

CREATE POLICY showroom_branding_update ON showroom_branding FOR UPDATE
    USING (has_showroom_access(showroom_id))
    WITH CHECK (has_showroom_access(showroom_id));

-- ============================================
-- SHOWROOM USERS POLICIES
-- ============================================

-- Can see users from own showroom
CREATE POLICY showroom_users_select ON showroom_users FOR SELECT
    USING (
        is_super_admin()
        OR showroom_id IN (SELECT get_user_showroom_ids())
    );

-- Super admins or primary owners can add users
CREATE POLICY showroom_users_insert ON showroom_users FOR INSERT
    WITH CHECK (
        is_super_admin()
        OR showroom_id IN (SELECT get_user_showroom_ids())
    );

CREATE POLICY showroom_users_update ON showroom_users FOR UPDATE
    USING (is_super_admin() OR showroom_id IN (SELECT get_user_showroom_ids()))
    WITH CHECK (is_super_admin() OR showroom_id IN (SELECT get_user_showroom_ids()));

-- ============================================
-- SHOWROOM CATEGORIES POLICIES
-- ============================================

CREATE POLICY showroom_categories_select ON showroom_categories FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY showroom_categories_insert ON showroom_categories FOR INSERT
    WITH CHECK (has_showroom_access(showroom_id));

CREATE POLICY showroom_categories_update ON showroom_categories FOR UPDATE
    USING (has_showroom_access(showroom_id))
    WITH CHECK (has_showroom_access(showroom_id));

CREATE POLICY showroom_categories_delete ON showroom_categories FOR DELETE
    USING (has_showroom_access(showroom_id));

-- ============================================
-- PRODUCTS POLICIES
-- ============================================

CREATE POLICY products_select ON products FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY products_insert ON products FOR INSERT
    WITH CHECK (has_showroom_access(showroom_id));

CREATE POLICY products_update ON products FOR UPDATE
    USING (has_showroom_access(showroom_id))
    WITH CHECK (has_showroom_access(showroom_id));

CREATE POLICY products_delete ON products FOR DELETE
    USING (has_showroom_access(showroom_id));

-- ============================================
-- PROJECTS POLICIES
-- ============================================

CREATE POLICY projects_select ON projects FOR SELECT
    USING (has_showroom_access(showroom_id));

-- Projects are created via anon access (customers) - handled by Edge Function
CREATE POLICY projects_insert ON projects FOR INSERT
    WITH CHECK (true); -- Controlled by Edge Function

CREATE POLICY projects_update ON projects FOR UPDATE
    USING (has_showroom_access(showroom_id))
    WITH CHECK (has_showroom_access(showroom_id));

-- ============================================
-- PROJECT MEASUREMENTS POLICIES
-- ============================================

CREATE POLICY project_measurements_select ON project_measurements FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id
            AND has_showroom_access(p.showroom_id)
        )
    );

CREATE POLICY project_measurements_insert ON project_measurements FOR INSERT
    WITH CHECK (true); -- Controlled by Edge Function

-- ============================================
-- PROJECT SELECTIONS POLICIES
-- ============================================

CREATE POLICY project_selections_select ON project_selections FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id
            AND has_showroom_access(p.showroom_id)
        )
    );

CREATE POLICY project_selections_insert ON project_selections FOR INSERT
    WITH CHECK (true); -- Controlled by Edge Function

-- ============================================
-- PUBLIC ACCESS FOR iOS APP (Anon Users)
-- ============================================

-- iOS app needs to fetch showroom config by code (no auth required)
CREATE POLICY showrooms_anon_select ON showrooms FOR SELECT TO anon
    USING (is_active = true);

-- iOS needs branding for any active showroom
CREATE POLICY showroom_branding_anon_select ON showroom_branding FOR SELECT TO anon
    USING (
        EXISTS (
            SELECT 1 FROM showrooms s
            WHERE s.id = showroom_id
            AND s.is_active = true
        )
    );

-- iOS needs to see enabled categories for showrooms
CREATE POLICY showroom_categories_anon_select ON showroom_categories FOR SELECT TO anon
    USING (
        is_enabled = true
        AND EXISTS (
            SELECT 1 FROM showrooms s
            WHERE s.id = showroom_id
            AND s.is_active = true
        )
    );

-- iOS needs to see active products
CREATE POLICY products_anon_select ON products FOR SELECT TO anon
    USING (
        is_active = true
        AND EXISTS (
            SELECT 1 FROM showrooms s
            WHERE s.id = showroom_id
            AND s.is_active = true
        )
    );

-- Categories are public (for reference data)
CREATE POLICY categories_anon_select ON categories FOR SELECT TO anon
    USING (is_active = true);
