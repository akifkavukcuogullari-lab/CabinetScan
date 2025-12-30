-- ============================================
-- CUSTOM ADDON ITEMS
-- Simple yes/no questions with quantities (e.g., "Add trash can?")
-- Appear after product selections in iOS app
-- ============================================

-- Showroom's custom addon questions
CREATE TABLE showroom_addons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    -- Question details
    question TEXT NOT NULL, -- e.g., "Add trash can?"
    description TEXT, -- Optional description
    unit TEXT NOT NULL DEFAULT 'pieces', -- e.g., "pieces", "units"

    -- Display settings
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    display_order INT NOT NULL DEFAULT 0,

    -- Optional pricing
    price_per_unit DECIMAL(10,2), -- Optional price for quoting

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Customer responses to addon questions
CREATE TABLE project_addons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    showroom_addon_id UUID NOT NULL REFERENCES showroom_addons(id) ON DELETE CASCADE,

    -- Customer response
    answer BOOLEAN NOT NULL DEFAULT false, -- Yes/No
    quantity INT NOT NULL DEFAULT 0, -- How many
    notes TEXT, -- Optional customer notes

    -- Snapshot for historical data
    question_snapshot TEXT NOT NULL,
    unit_snapshot TEXT NOT NULL,
    price_snapshot DECIMAL(10,2),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_showroom_addons_showroom ON showroom_addons(showroom_id);
CREATE INDEX idx_showroom_addons_enabled ON showroom_addons(showroom_id, is_enabled);
CREATE INDEX idx_project_addons_project ON project_addons(project_id);

-- Trigger for updated_at
CREATE TRIGGER update_showroom_addons_updated_at
    BEFORE UPDATE ON showroom_addons
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE showroom_addons ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_addons ENABLE ROW LEVEL SECURITY;

-- Showroom owners can manage their addons
CREATE POLICY showroom_addons_select ON showroom_addons FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY showroom_addons_insert ON showroom_addons FOR INSERT
    WITH CHECK (has_showroom_access(showroom_id));

CREATE POLICY showroom_addons_update ON showroom_addons FOR UPDATE
    USING (has_showroom_access(showroom_id));

CREATE POLICY showroom_addons_delete ON showroom_addons FOR DELETE
    USING (has_showroom_access(showroom_id));

-- iOS app can read enabled addons (anon access)
CREATE POLICY showroom_addons_anon_select ON showroom_addons FOR SELECT
    USING (is_enabled = true);

-- Project addons - showroom owners can view
CREATE POLICY project_addons_select ON project_addons FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id
            AND has_showroom_access(p.showroom_id)
        )
    );

-- iOS app can insert project addons (anon access)
CREATE POLICY project_addons_insert ON project_addons FOR INSERT
    WITH CHECK (true);
