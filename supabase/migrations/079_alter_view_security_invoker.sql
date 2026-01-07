-- ============================================
-- ALTER VIEW to set SECURITY INVOKER
-- Using ALTER VIEW SET instead of CREATE VIEW WITH
-- ============================================

-- Set security_invoker option on existing view
ALTER VIEW showroom_usage_summary SET (security_invoker = on);
