-- ============================================
-- Fix orphan projects from customers migration
-- Migration: 014_fix_orphan_projects
-- ============================================

-- Create legacy customers for orphan projects
-- Each orphan project gets its own unique customer
DO $$
DECLARE
    proj RECORD;
    new_customer_id UUID;
BEGIN
    FOR proj IN
        SELECT * FROM projects WHERE customer_id IS NULL
    LOOP
        -- Create a unique customer for this project
        INSERT INTO customers (
            showroom_id,
            phone,
            phone_normalized,
            first_name,
            last_name,
            email,
            customer_type,
            notes
        ) VALUES (
            proj.showroom_id,
            COALESCE(proj.customer_phone, 'LEGACY-' || proj.id),
            'LEGACY-' || proj.id,  -- Unique per project
            COALESCE(proj.customer_first_name, 'Unknown'),
            COALESCE(proj.customer_last_name, 'Customer'),
            proj.customer_email,
            'homeowner',
            'Migrated from legacy project: ' || proj.reference_number
        )
        RETURNING id INTO new_customer_id;

        -- Link the project
        UPDATE projects SET customer_id = new_customer_id WHERE id = proj.id;

        RAISE NOTICE 'Created customer % for project %', new_customer_id, proj.reference_number;
    END LOOP;
END $$;

-- Verify no orphan projects remain
DO $$
DECLARE
    orphan_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO orphan_count FROM projects WHERE customer_id IS NULL;

    IF orphan_count > 0 THEN
        RAISE EXCEPTION 'Still have % orphan projects', orphan_count;
    ELSE
        RAISE NOTICE 'All projects now have customers!';
    END IF;
END $$;
