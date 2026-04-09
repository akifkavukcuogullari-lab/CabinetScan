-- Replace single design_request config with per-priority pricing
-- Low: 2-3 business days, $10
-- Normal: 1 business day, $15
-- High: 3 hours, $20
-- Urgent: 1 hour, $25

-- Remove old single row
DELETE FROM credit_service_config WHERE service_type = 'design_request';

-- Update check constraint to allow priority-specific types
ALTER TABLE credit_service_config
  DROP CONSTRAINT IF EXISTS credit_service_config_service_type_check;

ALTER TABLE credit_service_config
  ADD CONSTRAINT credit_service_config_service_type_check
  CHECK (service_type IN ('vapi_call', 'twilio_sms', 'design_low', 'design_normal', 'design_high', 'design_urgent'));

-- Also update transactions table constraint
ALTER TABLE showroom_credit_transactions
  DROP CONSTRAINT IF EXISTS showroom_credit_transactions_service_type_check;

ALTER TABLE showroom_credit_transactions
  ADD CONSTRAINT showroom_credit_transactions_service_type_check
  CHECK (service_type IN ('vapi_call', 'twilio_sms', 'design_low', 'design_normal', 'design_high', 'design_urgent'));

-- Insert per-priority rows (cost = what platform pays, multiplier applied for showroom price)
INSERT INTO credit_service_config (service_type, cost_per_unit_cents, unit_description, multiplier, minimum_charge_cents) VALUES
  ('design_low', 667, '2-3 business days', 1.50, 1000),       -- $6.67 cost → $10 to showroom
  ('design_normal', 1000, '1 business day', 1.50, 1500),      -- $10 cost → $15 to showroom
  ('design_high', 1333, '3 hours', 1.50, 2000),               -- $13.33 cost → $20 to showroom
  ('design_urgent', 1667, '1 hour', 1.50, 2500);              -- $16.67 cost → $25 to showroom

-- Update the trigger to use priority-based pricing
CREATE OR REPLACE FUNCTION trigger_credit_deduct_on_design_request()
RETURNS TRIGGER AS $$
DECLARE
  v_config RECORD;
  v_service_type TEXT;
  v_billed INTEGER;
  v_actual INTEGER;
BEGIN
  -- Map priority to service type
  v_service_type := 'design_' || COALESCE(NEW.priority, 'normal');

  SELECT cost_per_unit_cents, multiplier, minimum_charge_cents INTO v_config
  FROM credit_service_config WHERE service_type = v_service_type;

  -- Fallback to design_normal if priority not found
  IF v_config IS NULL THEN
    SELECT cost_per_unit_cents, multiplier, minimum_charge_cents INTO v_config
    FROM credit_service_config WHERE service_type = 'design_normal';
  END IF;

  IF v_config IS NULL THEN
    RETURN NEW;
  END IF;

  v_actual := v_config.cost_per_unit_cents;
  v_billed := GREATEST(
    CEIL(v_config.cost_per_unit_cents * v_config.multiplier),
    v_config.minimum_charge_cents
  );

  PERFORM deduct_showroom_credit(
    NEW.showroom_id,
    v_billed,
    v_actual,
    v_billed,
    v_config.multiplier,
    v_service_type,
    NEW.id,
    'design_request',
    'Design request (' || COALESCE(NEW.priority, 'normal') || ')'
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
