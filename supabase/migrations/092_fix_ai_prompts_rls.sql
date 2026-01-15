-- Fix RLS policy for ai_system_prompts to allow super admins to update
-- The is_super_admin() function may not work correctly in some contexts

-- Drop the existing policy that uses the function
DROP POLICY IF EXISTS "Super admins manage prompts" ON ai_system_prompts;

-- Create a new policy that directly checks the admins table
CREATE POLICY "Super admins manage prompts" ON ai_system_prompts
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM admins
      WHERE admins.user_id = auth.uid()
      AND admins.is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admins
      WHERE admins.user_id = auth.uid()
      AND admins.is_active = true
    )
  );
