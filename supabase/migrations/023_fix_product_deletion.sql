-- ============================================
-- NEXTLEAN SCAN - FIX PRODUCT DELETION
-- Migration: 023_fix_product_deletion
-- ============================================

-- Add DELETE policy for project_selections
-- This allows showroom owners to delete selections for their projects
CREATE POLICY project_selections_delete ON project_selections FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id
            AND has_showroom_access(p.showroom_id)
        )
    );

-- Change the foreign key constraint from RESTRICT to SET NULL
-- This allows products to be deleted while preserving selection history
-- The product_name_snapshot and product_price_snapshot fields already preserve the data
ALTER TABLE project_selections
    DROP CONSTRAINT project_selections_product_id_fkey;

ALTER TABLE project_selections
    ADD CONSTRAINT project_selections_product_id_fkey
    FOREIGN KEY (product_id)
    REFERENCES products(id)
    ON DELETE SET NULL;

-- Make product_id nullable to support SET NULL behavior
ALTER TABLE project_selections
    ALTER COLUMN product_id DROP NOT NULL;
