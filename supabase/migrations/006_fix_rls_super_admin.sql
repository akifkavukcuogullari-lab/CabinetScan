-- ============================================
-- NEXTLEAN SCAN - FIX SUPER ADMIN RLS POLICIES
-- Migration: 006_fix_rls_super_admin
--
-- Fixes the RLS policy violation when super admins try to create showrooms.
-- The issue is that the is_super_admin() function, despite being SECURITY DEFINER,
-- may still face RLS evaluation issues when called during INSERT operations.
--
-- Solution:
-- 1. Drop all dependent policies first
-- 2. Recreate is_super_admin() with explicit search_path to prevent security issues
-- 3. Recreate all policies
-- ============================================

-- ============================================
-- STEP 1: DROP ALL DEPENDENT POLICIES
-- ============================================

-- Drop admins policies
DROP POLICY IF EXISTS admins_select ON admins;
DROP POLICY IF EXISTS admins_insert ON admins;
DROP POLICY IF EXISTS admins_update ON admins;

-- Drop categories policies
DROP POLICY IF EXISTS categories_select ON categories;
DROP POLICY IF EXISTS categories_insert ON categories;
DROP POLICY IF EXISTS categories_update ON categories;
DROP POLICY IF EXISTS categories_delete ON categories;

-- Drop showrooms policies
DROP POLICY IF EXISTS showrooms_select ON showrooms;
DROP POLICY IF EXISTS showrooms_insert ON showrooms;
DROP POLICY IF EXISTS showrooms_update ON showrooms;
DROP POLICY IF EXISTS showrooms_delete ON showrooms;
DROP POLICY IF EXISTS showrooms_anon_select ON showrooms;

-- Drop showroom_users policies
DROP POLICY IF EXISTS showroom_users_select ON showroom_users;
DROP POLICY IF EXISTS showroom_users_insert ON showroom_users;
DROP POLICY IF EXISTS showroom_users_update ON showroom_users;

-- Drop showroom_branding policies
DROP POLICY IF EXISTS showroom_branding_select ON showroom_branding;
DROP POLICY IF EXISTS showroom_branding_insert ON showroom_branding;
DROP POLICY IF EXISTS showroom_branding_update ON showroom_branding;

-- Drop showroom_categories policies
DROP POLICY IF EXISTS showroom_categories_select ON showroom_categories;
DROP POLICY IF EXISTS showroom_categories_insert ON showroom_categories;
DROP POLICY IF EXISTS showroom_categories_update ON showroom_categories;
DROP POLICY IF EXISTS showroom_categories_delete ON showroom_categories;

-- Drop products policies
DROP POLICY IF EXISTS products_select ON products;
DROP POLICY IF EXISTS products_insert ON products;
DROP POLICY IF EXISTS products_update ON products;
DROP POLICY IF EXISTS products_delete ON products;

-- Drop projects policies
DROP POLICY IF EXISTS projects_select ON projects;
DROP POLICY IF EXISTS projects_insert ON projects;
DROP POLICY IF EXISTS projects_update ON projects;

-- Drop project_measurements policies
DROP POLICY IF EXISTS project_measurements_select ON project_measurements;
DROP POLICY IF EXISTS project_measurements_insert ON project_measurements;

-- Drop project_selections policies
DROP POLICY IF EXISTS project_selections_select ON project_selections;
DROP POLICY IF EXISTS project_selections_insert ON project_selections;

-- Drop anon policies (from the original migration)
DROP POLICY IF EXISTS showroom_branding_anon_select ON showroom_branding;
DROP POLICY IF EXISTS showroom_categories_anon_select ON showroom_categories;
DROP POLICY IF EXISTS products_anon_select ON products;
DROP POLICY IF EXISTS categories_anon_select ON categories;

-- Drop storage policies that depend on is_super_admin
DROP POLICY IF EXISTS logos_authenticated_insert ON storage.objects;
DROP POLICY IF EXISTS logos_authenticated_update ON storage.objects;
DROP POLICY IF EXISTS logos_authenticated_delete ON storage.objects;
DROP POLICY IF EXISTS products_authenticated_insert ON storage.objects;
DROP POLICY IF EXISTS products_authenticated_update ON storage.objects;
DROP POLICY IF EXISTS products_authenticated_delete ON storage.objects;
DROP POLICY IF EXISTS scans_authenticated_select ON storage.objects;
DROP POLICY IF EXISTS scans_authenticated_delete ON storage.objects;

-- Drop showroom_invitations policies
DROP POLICY IF EXISTS showroom_invitations_admin_all ON showroom_invitations;
DROP POLICY IF EXISTS showroom_invitations_owner_select ON showroom_invitations;

-- ============================================
-- STEP 2: DROP AND RECREATE HELPER FUNCTIONS
-- ============================================

-- Drop existing functions
DROP FUNCTION IF EXISTS is_super_admin();
DROP FUNCTION IF EXISTS has_showroom_access(UUID);
DROP FUNCTION IF EXISTS get_user_showroom_ids();

-- Recreate is_super_admin() with proper security settings
-- SECURITY DEFINER runs as the function owner (postgres), bypassing RLS
-- SET search_path prevents search_path injection attacks
CREATE OR REPLACE FUNCTION is_super_admin()
RETURNS BOOLEAN AS $$
DECLARE
    user_is_admin BOOLEAN;
BEGIN
    -- Return false if no user is authenticated
    IF auth.uid() IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check if user exists in admins table and is active
    -- This executes as the function owner, bypassing RLS on admins table
    SELECT EXISTS (
        SELECT 1 FROM public.admins
        WHERE user_id = auth.uid()
        AND is_active = true
    ) INTO user_is_admin;

    RETURN COALESCE(user_is_admin, FALSE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

-- Grant execute permission to authenticated and anon users
GRANT EXECUTE ON FUNCTION is_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION is_super_admin() TO anon;

-- Recreate has_showroom_access with proper settings
CREATE OR REPLACE FUNCTION has_showroom_access(p_showroom_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    has_access BOOLEAN;
BEGIN
    -- Return false if no user is authenticated
    IF auth.uid() IS NULL THEN
        RETURN FALSE;
    END IF;

    -- First check if user is super admin (has access to all)
    IF is_super_admin() THEN
        RETURN TRUE;
    END IF;

    -- Then check if user is a showroom user for this showroom
    SELECT EXISTS (
        SELECT 1 FROM public.showroom_users
        WHERE user_id = auth.uid()
        AND showroom_id = p_showroom_id
        AND is_active = true
    ) INTO has_access;

    RETURN COALESCE(has_access, FALSE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION has_showroom_access(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION has_showroom_access(UUID) TO anon;

-- Recreate get_user_showroom_ids with proper settings
CREATE OR REPLACE FUNCTION get_user_showroom_ids()
RETURNS SETOF UUID AS $$
BEGIN
    -- Return empty if no user is authenticated
    IF auth.uid() IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT showroom_id FROM public.showroom_users
    WHERE user_id = auth.uid()
    AND is_active = true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_user_showroom_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_showroom_ids() TO anon;

-- ============================================
-- STEP 3: RECREATE ALL POLICIES
-- ============================================

-- ============================================
-- ADMINS POLICIES
-- ============================================

-- SELECT: Super admins see all, users can see their own record
CREATE POLICY admins_select ON admins FOR SELECT
    TO authenticated
    USING (is_super_admin() OR user_id = auth.uid());

-- INSERT: Only existing super admins can create new admins
CREATE POLICY admins_insert ON admins FOR INSERT
    TO authenticated
    WITH CHECK (is_super_admin());

-- UPDATE: Super admins can update any, users can update their own profile
CREATE POLICY admins_update ON admins FOR UPDATE
    TO authenticated
    USING (is_super_admin() OR user_id = auth.uid())
    WITH CHECK (is_super_admin() OR user_id = auth.uid());

-- ============================================
-- CATEGORIES POLICIES (Super Admin managed, public read)
-- ============================================

-- Anyone authenticated can read active categories
CREATE POLICY categories_select ON categories FOR SELECT
    TO authenticated
    USING (is_active = true OR is_super_admin());

-- Only super admins can manage categories
CREATE POLICY categories_insert ON categories FOR INSERT
    TO authenticated
    WITH CHECK (is_super_admin());

CREATE POLICY categories_update ON categories FOR UPDATE
    TO authenticated
    USING (is_super_admin())
    WITH CHECK (is_super_admin());

CREATE POLICY categories_delete ON categories FOR DELETE
    TO authenticated
    USING (is_super_admin());

-- ============================================
-- SHOWROOMS POLICIES
-- ============================================

-- SELECT: Super admins see all, showroom users see their own
CREATE POLICY showrooms_select ON showrooms FOR SELECT
    TO authenticated
    USING (
        is_super_admin()
        OR id IN (SELECT get_user_showroom_ids())
    );

-- INSERT: Only super admins can create showrooms
CREATE POLICY showrooms_insert ON showrooms FOR INSERT
    TO authenticated
    WITH CHECK (is_super_admin());

-- UPDATE: Super admins can update any, showroom owners their own
CREATE POLICY showrooms_update ON showrooms FOR UPDATE
    TO authenticated
    USING (has_showroom_access(id))
    WITH CHECK (has_showroom_access(id));

-- DELETE: Only super admins can delete showrooms
CREATE POLICY showrooms_delete ON showrooms FOR DELETE
    TO authenticated
    USING (is_super_admin());

-- Anonymous users can view active showrooms (for iOS app)
CREATE POLICY showrooms_anon_select ON showrooms FOR SELECT
    TO anon
    USING (is_active = true);

-- ============================================
-- SHOWROOM BRANDING POLICIES
-- ============================================

CREATE POLICY showroom_branding_select ON showroom_branding FOR SELECT
    TO authenticated
    USING (has_showroom_access(showroom_id));

CREATE POLICY showroom_branding_insert ON showroom_branding FOR INSERT
    TO authenticated
    WITH CHECK (has_showroom_access(showroom_id));

CREATE POLICY showroom_branding_update ON showroom_branding FOR UPDATE
    TO authenticated
    USING (has_showroom_access(showroom_id))
    WITH CHECK (has_showroom_access(showroom_id));

-- ============================================
-- SHOWROOM USERS POLICIES
-- ============================================

-- Can see users from own showroom
CREATE POLICY showroom_users_select ON showroom_users FOR SELECT
    TO authenticated
    USING (
        is_super_admin()
        OR showroom_id IN (SELECT get_user_showroom_ids())
    );

-- Super admins or showroom members can add users
CREATE POLICY showroom_users_insert ON showroom_users FOR INSERT
    TO authenticated
    WITH CHECK (
        is_super_admin()
        OR showroom_id IN (SELECT get_user_showroom_ids())
    );

CREATE POLICY showroom_users_update ON showroom_users FOR UPDATE
    TO authenticated
    USING (is_super_admin() OR showroom_id IN (SELECT get_user_showroom_ids()))
    WITH CHECK (is_super_admin() OR showroom_id IN (SELECT get_user_showroom_ids()));

-- ============================================
-- SHOWROOM CATEGORIES POLICIES
-- ============================================

CREATE POLICY showroom_categories_select ON showroom_categories FOR SELECT
    TO authenticated
    USING (has_showroom_access(showroom_id));

CREATE POLICY showroom_categories_insert ON showroom_categories FOR INSERT
    TO authenticated
    WITH CHECK (has_showroom_access(showroom_id));

CREATE POLICY showroom_categories_update ON showroom_categories FOR UPDATE
    TO authenticated
    USING (has_showroom_access(showroom_id))
    WITH CHECK (has_showroom_access(showroom_id));

CREATE POLICY showroom_categories_delete ON showroom_categories FOR DELETE
    TO authenticated
    USING (has_showroom_access(showroom_id));

-- ============================================
-- PRODUCTS POLICIES
-- ============================================

CREATE POLICY products_select ON products FOR SELECT
    TO authenticated
    USING (has_showroom_access(showroom_id));

CREATE POLICY products_insert ON products FOR INSERT
    TO authenticated
    WITH CHECK (has_showroom_access(showroom_id));

CREATE POLICY products_update ON products FOR UPDATE
    TO authenticated
    USING (has_showroom_access(showroom_id))
    WITH CHECK (has_showroom_access(showroom_id));

CREATE POLICY products_delete ON products FOR DELETE
    TO authenticated
    USING (has_showroom_access(showroom_id));

-- ============================================
-- PROJECTS POLICIES
-- ============================================

CREATE POLICY projects_select ON projects FOR SELECT
    TO authenticated
    USING (has_showroom_access(showroom_id));

-- Projects are created via anon access (customers) - handled by Edge Function
CREATE POLICY projects_insert ON projects FOR INSERT
    TO authenticated
    WITH CHECK (true); -- Controlled by Edge Function

CREATE POLICY projects_update ON projects FOR UPDATE
    TO authenticated
    USING (has_showroom_access(showroom_id))
    WITH CHECK (has_showroom_access(showroom_id));

-- ============================================
-- PROJECT MEASUREMENTS POLICIES
-- ============================================

CREATE POLICY project_measurements_select ON project_measurements FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id
            AND has_showroom_access(p.showroom_id)
        )
    );

CREATE POLICY project_measurements_insert ON project_measurements FOR INSERT
    TO authenticated
    WITH CHECK (true); -- Controlled by Edge Function

-- ============================================
-- PROJECT SELECTIONS POLICIES
-- ============================================

CREATE POLICY project_selections_select ON project_selections FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id
            AND has_showroom_access(p.showroom_id)
        )
    );

CREATE POLICY project_selections_insert ON project_selections FOR INSERT
    TO authenticated
    WITH CHECK (true); -- Controlled by Edge Function

-- ============================================
-- PUBLIC ACCESS FOR iOS APP (Anon Users)
-- ============================================

-- iOS needs branding for any active showroom
CREATE POLICY showroom_branding_anon_select ON showroom_branding FOR SELECT
    TO anon
    USING (
        EXISTS (
            SELECT 1 FROM showrooms s
            WHERE s.id = showroom_id
            AND s.is_active = true
        )
    );

-- iOS needs to see enabled categories for showrooms
CREATE POLICY showroom_categories_anon_select ON showroom_categories FOR SELECT
    TO anon
    USING (
        is_enabled = true
        AND EXISTS (
            SELECT 1 FROM showrooms s
            WHERE s.id = showroom_id
            AND s.is_active = true
        )
    );

-- iOS needs to see active products
CREATE POLICY products_anon_select ON products FOR SELECT
    TO anon
    USING (
        is_active = true
        AND EXISTS (
            SELECT 1 FROM showrooms s
            WHERE s.id = showroom_id
            AND s.is_active = true
        )
    );

-- Categories are public (for reference data)
CREATE POLICY categories_anon_select ON categories FOR SELECT
    TO anon
    USING (is_active = true);

-- ============================================
-- STORAGE POLICIES (Recreate what was dropped)
-- ============================================

-- Logos bucket - authenticated users with showroom access can manage
CREATE POLICY logos_authenticated_insert ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'logos'
        AND is_super_admin()
    );

CREATE POLICY logos_authenticated_update ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'logos'
        AND is_super_admin()
    )
    WITH CHECK (
        bucket_id = 'logos'
        AND is_super_admin()
    );

CREATE POLICY logos_authenticated_delete ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'logos'
        AND is_super_admin()
    );

-- Products bucket - showroom owners can manage their products
CREATE POLICY products_authenticated_insert ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'products'
        AND (is_super_admin() OR (storage.foldername(name))[1] IN (SELECT get_user_showroom_ids()::text))
    );

CREATE POLICY products_authenticated_update ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'products'
        AND (is_super_admin() OR (storage.foldername(name))[1] IN (SELECT get_user_showroom_ids()::text))
    )
    WITH CHECK (
        bucket_id = 'products'
        AND (is_super_admin() OR (storage.foldername(name))[1] IN (SELECT get_user_showroom_ids()::text))
    );

CREATE POLICY products_authenticated_delete ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'products'
        AND (is_super_admin() OR (storage.foldername(name))[1] IN (SELECT get_user_showroom_ids()::text))
    );

-- Scans bucket - showroom owners can view their scans
CREATE POLICY scans_authenticated_select ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'scans'
        AND (is_super_admin() OR (storage.foldername(name))[1] IN (SELECT get_user_showroom_ids()::text))
    );

CREATE POLICY scans_authenticated_delete ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'scans'
        AND (is_super_admin() OR (storage.foldername(name))[1] IN (SELECT get_user_showroom_ids()::text))
    );

-- ============================================
-- SHOWROOM INVITATIONS POLICIES
-- ============================================

-- Super admin full access
CREATE POLICY showroom_invitations_admin_all ON showroom_invitations
    FOR ALL
    TO authenticated
    USING (is_super_admin())
    WITH CHECK (is_super_admin());

-- Showroom owners can view invitations for their showrooms
CREATE POLICY showroom_invitations_owner_select ON showroom_invitations
    FOR SELECT
    TO authenticated
    USING (showroom_id IN (SELECT get_user_showroom_ids()));

-- ============================================
-- ADD COMMENTS FOR DOCUMENTATION
-- ============================================

COMMENT ON FUNCTION is_super_admin() IS
'Returns TRUE if the current authenticated user is an active super admin.
Uses SECURITY DEFINER to bypass RLS when querying the admins table.';

COMMENT ON FUNCTION has_showroom_access(UUID) IS
'Returns TRUE if the current user has access to the specified showroom.
Super admins have access to all showrooms. Showroom users have access to their assigned showrooms.';

COMMENT ON FUNCTION get_user_showroom_ids() IS
'Returns the IDs of all showrooms the current user has access to.
Used in RLS policies for showroom-scoped queries.';
