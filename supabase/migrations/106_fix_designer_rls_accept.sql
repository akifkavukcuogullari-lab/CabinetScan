-- Fix: Allow designers to accept pending requests from the pool
-- The original policy required designer_id = get_designer_id(), but designer_id is NULL on pending requests
-- This adds OR status = 'pending' so any designer can claim a pending request

DROP POLICY IF EXISTS design_requests_designer_update ON design_requests;
CREATE POLICY design_requests_designer_update ON design_requests FOR UPDATE TO authenticated
    USING (
        is_designer() AND (
            designer_id = get_designer_id()  -- own accepted requests
            OR status = 'pending'            -- allow claiming pending requests from pool
        )
    );
