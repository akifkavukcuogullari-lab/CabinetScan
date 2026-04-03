-- Update designer_project_view to include estimated_completion_at and drop_reason
-- Must drop and recreate because CREATE OR REPLACE cannot add columns

DROP VIEW IF EXISTS designer_project_view;

CREATE VIEW designer_project_view AS
SELECT
    p.id,
    p.reference_number,
    p.project_name,
    p.project_notes,
    p.status,
    p.created_at,
    dr.id as design_request_id,
    dr.status as design_status,
    dr.priority,
    dr.notes as design_notes,
    dr.designer_id,
    dr.accepted_at,
    dr.delivered_at,
    dr.estimated_completion_at,
    dr.drop_reason,
    dr.created_at as request_created_at
FROM projects p
JOIN design_requests dr ON dr.project_id = p.id
WHERE dr.status = 'pending'
   OR dr.designer_id = get_designer_id();
