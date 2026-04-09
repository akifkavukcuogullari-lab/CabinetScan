-- Add new project status values for design workflow
ALTER TYPE project_status ADD VALUE IF NOT EXISTS 'design_requested' AFTER 'submitted';
ALTER TYPE project_status ADD VALUE IF NOT EXISTS 'design_completed' AFTER 'design_requested';
