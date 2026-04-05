-- Migration: Add project_whiteboards table
-- Files stored in existing 'scans' bucket under whiteboards/ prefix

-- 1. Create the project_whiteboards table
CREATE TABLE project_whiteboards (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    entry_type TEXT NOT NULL CHECK (entry_type IN ('drawing', 'photo')),
    title TEXT,
    drawing_data_url TEXT,
    thumbnail_url TEXT,
    photo_url TEXT,
    created_by_showroom_user_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_project_whiteboards_project_id ON project_whiteboards(project_id);

-- 2. Enable RLS
ALTER TABLE project_whiteboards ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies (same pattern as project_measurements)
CREATE POLICY "Staff can read project whiteboards"
    ON project_whiteboards FOR SELECT
    USING (
        project_id IN (
            SELECT id FROM projects WHERE showroom_id IN (
                SELECT showroom_id FROM showroom_users WHERE user_id = auth.uid()
            )
        )
    );

CREATE POLICY "Staff can insert project whiteboards"
    ON project_whiteboards FOR INSERT
    WITH CHECK (
        project_id IN (
            SELECT id FROM projects WHERE showroom_id IN (
                SELECT showroom_id FROM showroom_users WHERE user_id = auth.uid()
            )
        )
    );

CREATE POLICY "Staff can update own whiteboards"
    ON project_whiteboards FOR UPDATE
    USING (
        created_by_showroom_user_id IN (
            SELECT id FROM showroom_users WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Staff can delete own whiteboards"
    ON project_whiteboards FOR DELETE
    USING (
        created_by_showroom_user_id IN (
            SELECT id FROM showroom_users WHERE user_id = auth.uid()
        )
    );

-- 4. Designer read access (via design_requests)
CREATE POLICY "Designers can read project whiteboards"
    ON project_whiteboards FOR SELECT
    USING (
        project_id IN (
            SELECT project_id FROM design_requests
            WHERE designer_id IN (
                SELECT id FROM designers WHERE user_id = auth.uid()
            )
        )
    );
