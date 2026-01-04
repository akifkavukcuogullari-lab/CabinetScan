-- Project addon selections table
-- Stores customer's addon selections when submitting a project

CREATE TABLE IF NOT EXISTS project_addon_selections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  addon_id UUID NOT NULL REFERENCES showroom_addons(id) ON DELETE CASCADE,
  is_selected BOOLEAN NOT NULL DEFAULT false,
  quantity INTEGER NOT NULL DEFAULT 0,
  customer_notes TEXT, -- Optional notes from customer about this addon
  -- Snapshot fields (in case addon is modified/deleted later)
  addon_question_snapshot TEXT NOT NULL,
  addon_description_snapshot TEXT,
  addon_unit_snapshot TEXT NOT NULL DEFAULT 'pieces',
  addon_price_snapshot DECIMAL(10,2),
  addon_image_url_snapshot TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(project_id, addon_id)
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_project_addon_selections_project_id
  ON project_addon_selections(project_id);
CREATE INDEX IF NOT EXISTS idx_project_addon_selections_addon_id
  ON project_addon_selections(addon_id);

-- Enable RLS
ALTER TABLE project_addon_selections ENABLE ROW LEVEL SECURITY;

-- RLS policies for project_addon_selections
-- Showroom owners can view addon selections for their projects
CREATE POLICY "Showroom owners can view addon selections"
  ON project_addon_selections
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM projects p
      WHERE p.id = project_addon_selections.project_id
      AND has_showroom_access(p.showroom_id)
    )
  );

-- Super admins can do everything
CREATE POLICY "Super admins have full access to addon selections"
  ON project_addon_selections
  FOR ALL
  USING (is_super_admin());

-- Allow insert for service role (edge functions)
CREATE POLICY "Service role can insert addon selections"
  ON project_addon_selections
  FOR INSERT
  WITH CHECK (true);

-- Grant permissions
GRANT ALL ON project_addon_selections TO authenticated;
GRANT ALL ON project_addon_selections TO service_role;
