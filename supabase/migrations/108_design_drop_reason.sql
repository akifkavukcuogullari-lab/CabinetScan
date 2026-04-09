-- Add drop reason to design requests
-- When a designer drops a project, they must provide an explanation

ALTER TABLE design_requests ADD COLUMN drop_reason TEXT;
