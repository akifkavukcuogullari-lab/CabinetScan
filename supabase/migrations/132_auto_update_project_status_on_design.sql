-- Auto-update project status when design request status changes
-- INSERT → design_requested
-- delivered/completed → design_completed

CREATE OR REPLACE FUNCTION trigger_project_status_on_design_request()
RETURNS TRIGGER AS $$
BEGIN
  -- On INSERT: mark project as design_requested
  IF TG_OP = 'INSERT' THEN
    UPDATE projects SET status = 'design_requested' WHERE id = NEW.project_id;
  END IF;

  -- On UPDATE: track design lifecycle
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    CASE NEW.status
      WHEN 'accepted', 'in_progress', 'revision_requested' THEN
        UPDATE projects SET status = 'in_design' WHERE id = NEW.project_id;
      WHEN 'delivered' THEN
        UPDATE projects SET status = 'design_delivered' WHERE id = NEW.project_id;
      WHEN 'approved', 'completed' THEN
        UPDATE projects SET status = 'design_completed' WHERE id = NEW.project_id;
      WHEN 'canceled' THEN
        UPDATE projects SET status = 'submitted' WHERE id = NEW.project_id;
      ELSE
        NULL;
    END CASE;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop if exists to avoid duplicate
DROP TRIGGER IF EXISTS project_status_on_design_request ON design_requests;

CREATE TRIGGER project_status_on_design_request
  AFTER INSERT OR UPDATE ON design_requests
  FOR EACH ROW
  EXECUTE FUNCTION trigger_project_status_on_design_request();
