-- Add estimated completion time to design requests
-- Designers set this when accepting or working on a project
-- Showrooms can see it on the design status card

ALTER TABLE design_requests ADD COLUMN estimated_completion_at TIMESTAMPTZ;
