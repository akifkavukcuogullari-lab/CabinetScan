-- Replace single design_request price with per-priority pricing
-- Centralized in credit_service_config — change here and it affects everywhere

-- Update the CHECK constraint to allow new service types
ALTER TABLE credit_service_config DROP CONSTRAINT IF EXISTS credit_service_config_service_type_check;
ALTER TABLE credit_service_config ADD CONSTRAINT credit_service_config_service_type_check
  CHECK (service_type IN ('vapi_call', 'twilio_sms', 'design_request', 'design_low', 'design_normal', 'design_high', 'design_urgent'));

-- Also update transactions table constraint
ALTER TABLE showroom_credit_transactions DROP CONSTRAINT IF EXISTS showroom_credit_transactions_service_type_check;
ALTER TABLE showroom_credit_transactions ADD CONSTRAINT showroom_credit_transactions_service_type_check
  CHECK (service_type IN ('vapi_call', 'twilio_sms', 'design_request', 'design_low', 'design_normal', 'design_high', 'design_urgent'));

-- Insert per-priority pricing (keep the original design_request as fallback)
INSERT INTO credit_service_config (service_type, cost_per_unit_cents, unit_description, multiplier, minimum_charge_cents) VALUES
  ('design_low',    500,  'per request', 1.00, 500),
  ('design_normal', 1000, 'per request', 1.00, 1000),
  ('design_high',   1500, 'per request', 1.00, 1500),
  ('design_urgent', 2500, 'per request', 1.00, 2500)
ON CONFLICT (service_type) DO UPDATE SET
  cost_per_unit_cents = EXCLUDED.cost_per_unit_cents,
  multiplier = EXCLUDED.multiplier,
  minimum_charge_cents = EXCLUDED.minimum_charge_cents,
  updated_at = now();

-- Update the debit trigger to use priority-based pricing
CREATE OR REPLACE FUNCTION trigger_credit_deduct_on_design_request()
RETURNS TRIGGER AS $$
DECLARE
  v_config RECORD;
  v_billed INTEGER;
  v_actual INTEGER;
  v_service_type TEXT;
BEGIN
  -- Map priority to service type
  v_service_type := 'design_' || COALESCE(NEW.priority, 'normal');

  -- Look up priority-specific price, fallback to generic design_request
  SELECT cost_per_unit_cents, multiplier, minimum_charge_cents INTO v_config
  FROM credit_service_config
  WHERE service_type = v_service_type;

  IF v_config IS NULL THEN
    SELECT cost_per_unit_cents, multiplier, minimum_charge_cents INTO v_config
    FROM credit_service_config
    WHERE service_type = 'design_request';
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
    'Design request (' || COALESCE(NEW.priority, 'normal') || ' priority)'
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update the refund trigger to refund the actual charged amount (reads from transaction)
CREATE OR REPLACE FUNCTION trigger_credit_refund_on_design_cancel()
RETURNS TRIGGER AS $$
DECLARE
  v_txn RECORD;
BEGIN
  -- Find the original debit transaction for this design request
  SELECT billed_cost_cents INTO v_txn
  FROM showroom_credit_transactions
  WHERE reference_id = OLD.id
    AND reference_type = 'design_request'
    AND type = 'debit'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_txn IS NOT NULL AND v_txn.billed_cost_cents > 0 THEN
    PERFORM add_showroom_credit(
      OLD.showroom_id,
      v_txn.billed_cost_cents,
      'refund',
      NULL,
      'Design request canceled (' || COALESCE(OLD.priority, 'normal') || ' priority) — credit refunded'
    );
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
