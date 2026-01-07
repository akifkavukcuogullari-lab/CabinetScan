-- Add DELETE policy for projects table
-- Allows showroom owners to delete their own projects

CREATE POLICY projects_delete ON projects FOR DELETE
  USING (
    showroom_id IN (
      SELECT showroom_id FROM showroom_users WHERE user_id = auth.uid()
    )
    OR is_super_admin()
  );
