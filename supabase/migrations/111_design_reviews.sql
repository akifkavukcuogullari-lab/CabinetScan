-- Design reviews and rejection reasons
-- Showroom rates designer after accepting delivery (for monthly bonus)
-- Rejection keeps project with same designer (not back to pool)

CREATE TABLE design_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    design_request_id UUID NOT NULL REFERENCES design_requests(id) ON DELETE CASCADE,
    designer_id UUID NOT NULL REFERENCES designers(id),
    showroom_id UUID NOT NULL REFERENCES showrooms(id),

    -- Rating (1-5 stars)
    rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review_text TEXT,

    -- Who reviewed
    reviewed_by UUID REFERENCES auth.users(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT design_reviews_request_unique UNIQUE (design_request_id)
);

-- Add rejection reason to design_requests
ALTER TABLE design_requests ADD COLUMN rejection_reason TEXT;

-- Indexes
CREATE INDEX idx_design_reviews_designer ON design_reviews(designer_id);
CREATE INDEX idx_design_reviews_showroom ON design_reviews(showroom_id);

-- RLS
ALTER TABLE design_reviews ENABLE ROW LEVEL SECURITY;

-- Designers can see their own reviews
CREATE POLICY design_reviews_designer_select ON design_reviews FOR SELECT TO authenticated
    USING (is_designer() AND designer_id = get_designer_id());

-- Showroom users can see reviews for their showroom
CREATE POLICY design_reviews_showroom_select ON design_reviews FOR SELECT TO authenticated
    USING (has_showroom_access(showroom_id));

-- Super admins can see all reviews
CREATE POLICY design_reviews_admin_select ON design_reviews FOR SELECT TO authenticated
    USING (is_super_admin());

-- Showroom users can create reviews
CREATE POLICY design_reviews_insert ON design_reviews FOR INSERT TO authenticated
    WITH CHECK (has_showroom_access(showroom_id));
