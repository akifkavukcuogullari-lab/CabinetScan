-- Allow showroom users to delete their own pending design requests
CREATE POLICY design_requests_showroom_delete ON design_requests FOR DELETE TO authenticated
  USING (
    status = 'pending'
    AND (is_super_admin() OR has_showroom_access(showroom_id))
  );
