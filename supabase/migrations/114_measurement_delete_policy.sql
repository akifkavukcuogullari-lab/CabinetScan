-- Allow staff to delete measurements for projects in their showroom
-- Needed for rescan overwrite from iOS app

CREATE POLICY "Staff can delete project measurements"
    ON project_measurements FOR DELETE
    USING (
        project_id IN (
            SELECT id FROM projects WHERE showroom_id IN (
                SELECT showroom_id FROM showroom_users WHERE user_id = auth.uid()
            )
        )
    );
