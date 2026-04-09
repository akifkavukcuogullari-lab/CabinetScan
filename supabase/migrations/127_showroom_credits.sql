-- ===========================================================================
-- Showroom Credit System
-- Unified pre-paid balance for voice agent (Vapi+Twilio) and design requests
-- ===========================================================================

-- Ensure pg_net extension is available (for low-balance notifications)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ===========================================================================
-- 1. showroom_credit_balances — one wallet per showroom
-- ===========================================================================
CREATE TABLE showroom_credit_balances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  showroom_id UUID NOT NULL UNIQUE REFERENCES showrooms(id) ON DELETE CASCADE,
  balance_cents INTEGER NOT NULL DEFAULT 0,
  low_balance_threshold_cents INTEGER NOT NULL DEFAULT 1000, -- $10 default
  low_balance_notified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE showroom_credit_balances ENABLE ROW LEVEL SECURITY;

CREATE POLICY "credit_balances_select"
  ON showroom_credit_balances FOR SELECT
  USING (is_super_admin() OR has_showroom_access(showroom_id));

CREATE POLICY "credit_balances_update"
  ON showroom_credit_balances FOR UPDATE
  USING (is_super_admin() OR has_showroom_access(showroom_id));

CREATE POLICY "credit_balances_insert"
  ON showroom_credit_balances FOR INSERT
  WITH CHECK (is_super_admin());

CREATE POLICY "credit_balances_delete"
  ON showroom_credit_balances FOR DELETE
  USING (is_super_admin());

CREATE TRIGGER set_credit_balances_updated_at
  BEFORE UPDATE ON showroom_credit_balances
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ===========================================================================
-- 2. showroom_credit_transactions — immutable ledger
-- ===========================================================================
CREATE TABLE showroom_credit_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('top_up', 'deduction', 'adjustment', 'refund', 'plan_bonus')),
  amount_cents INTEGER NOT NULL,
  balance_after_cents INTEGER NOT NULL,
  actual_cost_cents INTEGER,
  billed_cost_cents INTEGER,
  multiplier DECIMAL(4,2),
  service_type TEXT CHECK (service_type IN ('vapi_call', 'twilio_sms', 'design_request')),
  reference_id UUID,
  reference_type TEXT CHECK (reference_type IN ('voice_agent_log', 'design_request')),
  stripe_payment_intent_id TEXT,
  stripe_checkout_session_id TEXT,
  performed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE showroom_credit_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "credit_txn_select"
  ON showroom_credit_transactions FOR SELECT
  USING (is_super_admin() OR has_showroom_access(showroom_id));

CREATE POLICY "credit_txn_insert"
  ON showroom_credit_transactions FOR INSERT
  WITH CHECK (is_super_admin());

CREATE POLICY "credit_txn_delete"
  ON showroom_credit_transactions FOR DELETE
  USING (is_super_admin());

CREATE INDEX idx_credit_txn_showroom_date ON showroom_credit_transactions(showroom_id, created_at DESC);
CREATE INDEX idx_credit_txn_reference ON showroom_credit_transactions(reference_id, reference_type);
CREATE INDEX idx_credit_txn_stripe ON showroom_credit_transactions(stripe_checkout_session_id) WHERE stripe_checkout_session_id IS NOT NULL;

-- ===========================================================================
-- 3. credit_service_config — cost/markup per service type
-- ===========================================================================
CREATE TABLE credit_service_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_type TEXT NOT NULL UNIQUE CHECK (service_type IN ('vapi_call', 'twilio_sms', 'design_request')),
  cost_per_unit_cents INTEGER NOT NULL,
  unit_description TEXT NOT NULL,
  multiplier DECIMAL(4,2) NOT NULL DEFAULT 2.00,
  minimum_charge_cents INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE credit_service_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "credit_config_select"
  ON credit_service_config FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "credit_config_all_super"
  ON credit_service_config FOR ALL
  USING (is_super_admin());

CREATE TRIGGER set_credit_config_updated_at
  BEFORE UPDATE ON credit_service_config
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Seed default costs
INSERT INTO credit_service_config (service_type, cost_per_unit_cents, unit_description, multiplier, minimum_charge_cents) VALUES
  ('vapi_call', 7, 'per minute', 2.00, 14),
  ('twilio_sms', 1, 'per message', 2.00, 2),
  ('design_request', 1000, 'per request', 1.50, 1500);

-- ===========================================================================
-- 4. credit_plan_bonuses — bonus credits per subscription plan
-- ===========================================================================
CREATE TABLE credit_plan_bonuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_plan TEXT NOT NULL,
  bonus_cents INTEGER NOT NULL,
  frequency TEXT NOT NULL CHECK (frequency IN ('one_time', 'monthly')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE credit_plan_bonuses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "credit_bonus_select"
  ON credit_plan_bonuses FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "credit_bonus_all_super"
  ON credit_plan_bonuses FOR ALL
  USING (is_super_admin());

CREATE TRIGGER set_credit_bonus_updated_at
  BEFORE UPDATE ON credit_plan_bonuses
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Seed plan bonuses
INSERT INTO credit_plan_bonuses (subscription_plan, bonus_cents, frequency) VALUES
  ('business', 2000, 'one_time'),
  ('enterprise', 5000, 'monthly');

-- ===========================================================================
-- 5. Core DB Functions
-- ===========================================================================

-- Deduct credits atomically (called by triggers)
CREATE OR REPLACE FUNCTION deduct_showroom_credit(
  p_showroom_id UUID,
  p_amount_cents INTEGER,
  p_actual_cost_cents INTEGER,
  p_billed_cost_cents INTEGER,
  p_multiplier DECIMAL,
  p_service_type TEXT,
  p_reference_id UUID,
  p_reference_type TEXT,
  p_notes TEXT DEFAULT NULL
) RETURNS TABLE(success BOOLEAN, new_balance_cents INTEGER, transaction_id UUID) AS $$
DECLARE
  v_balance INTEGER;
  v_new_balance INTEGER;
  v_txn_id UUID;
  v_threshold INTEGER;
  v_last_notified TIMESTAMPTZ;
  v_supabase_url TEXT;
  v_service_key TEXT;
BEGIN
  -- Lock row for atomic update
  SELECT balance_cents, low_balance_threshold_cents, low_balance_notified_at
  INTO v_balance, v_threshold, v_last_notified
  FROM showroom_credit_balances
  WHERE showroom_id = p_showroom_id
  FOR UPDATE;

  -- If no balance row exists, create one (starts at 0, will go negative)
  IF v_balance IS NULL THEN
    INSERT INTO showroom_credit_balances (showroom_id, balance_cents)
    VALUES (p_showroom_id, 0)
    ON CONFLICT (showroom_id) DO NOTHING;

    v_balance := 0;
    v_threshold := 1000;
    v_last_notified := NULL;
  END IF;

  -- Allow overdraft for completed services (call already happened)
  v_new_balance := v_balance - p_amount_cents;

  UPDATE showroom_credit_balances
  SET balance_cents = v_new_balance, updated_at = now()
  WHERE showroom_id = p_showroom_id;

  -- Record transaction
  INSERT INTO showroom_credit_transactions (
    showroom_id, type, amount_cents, balance_after_cents,
    actual_cost_cents, billed_cost_cents, multiplier,
    service_type, reference_id, reference_type, notes
  ) VALUES (
    p_showroom_id, 'deduction', -p_amount_cents, v_new_balance,
    p_actual_cost_cents, p_billed_cost_cents, p_multiplier,
    p_service_type, p_reference_id, p_reference_type, p_notes
  ) RETURNING id INTO v_txn_id;

  -- Low balance notification (max once per 24h)
  IF v_new_balance <= v_threshold
     AND (v_last_notified IS NULL OR v_last_notified < now() - INTERVAL '24 hours')
  THEN
    UPDATE showroom_credit_balances
    SET low_balance_notified_at = now()
    WHERE showroom_id = p_showroom_id;

    -- Fire async notification via pg_net
    SELECT value INTO v_supabase_url FROM system_config WHERE key = 'supabase_url';
    SELECT value INTO v_service_key FROM system_config WHERE key = 'service_role_key';

    IF v_supabase_url IS NOT NULL AND v_service_key IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_supabase_url || '/functions/v1/credit-low-balance-notify',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_key
        ),
        body := jsonb_build_object(
          'showroom_id', p_showroom_id,
          'balance_cents', v_new_balance,
          'threshold_cents', v_threshold
        )
      );
    END IF;
  END IF;

  RETURN QUERY SELECT true, v_new_balance, v_txn_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add credits atomically (top-ups, bonuses, adjustments)
CREATE OR REPLACE FUNCTION add_showroom_credit(
  p_showroom_id UUID,
  p_amount_cents INTEGER,
  p_type TEXT,
  p_performed_by UUID DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_stripe_session_id TEXT DEFAULT NULL
) RETURNS TABLE(success BOOLEAN, new_balance_cents INTEGER, transaction_id UUID) AS $$
DECLARE
  v_new_balance INTEGER;
  v_txn_id UUID;
  v_threshold INTEGER;
BEGIN
  -- Idempotency check for Stripe top-ups
  IF p_stripe_session_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM showroom_credit_transactions
      WHERE stripe_checkout_session_id = p_stripe_session_id
    ) THEN
      -- Already processed
      SELECT balance_cents INTO v_new_balance
      FROM showroom_credit_balances WHERE showroom_id = p_showroom_id;
      RETURN QUERY SELECT true, COALESCE(v_new_balance, 0), NULL::UUID;
      RETURN;
    END IF;
  END IF;

  -- Upsert balance row
  INSERT INTO showroom_credit_balances (showroom_id, balance_cents)
  VALUES (p_showroom_id, p_amount_cents)
  ON CONFLICT (showroom_id)
  DO UPDATE SET
    balance_cents = showroom_credit_balances.balance_cents + p_amount_cents,
    updated_at = now()
  RETURNING balance_cents, low_balance_threshold_cents INTO v_new_balance, v_threshold;

  -- Record transaction
  INSERT INTO showroom_credit_transactions (
    showroom_id, type, amount_cents, balance_after_cents,
    stripe_checkout_session_id, performed_by, notes
  ) VALUES (
    p_showroom_id, p_type, p_amount_cents, v_new_balance,
    p_stripe_session_id, p_performed_by, p_notes
  ) RETURNING id INTO v_txn_id;

  -- Clear low-balance notification if balance is above threshold
  IF v_new_balance > v_threshold THEN
    UPDATE showroom_credit_balances
    SET low_balance_notified_at = NULL
    WHERE showroom_id = p_showroom_id;
  END IF;

  RETURN QUERY SELECT true, v_new_balance, v_txn_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Quick balance check
CREATE OR REPLACE FUNCTION check_showroom_balance(p_showroom_id UUID, p_min_cents INTEGER DEFAULT 0)
RETURNS BOOLEAN AS $$
DECLARE
  v_balance INTEGER;
BEGIN
  SELECT balance_cents INTO v_balance
  FROM showroom_credit_balances
  WHERE showroom_id = p_showroom_id;

  RETURN COALESCE(v_balance, 0) > p_min_cents;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===========================================================================
-- 6. Trigger: Deduct on voice agent call completion
-- ===========================================================================
-- Fires when voice-agent-webhook sets call_duration_seconds.
-- Deducts SMS + call cost in ONE combined transaction.
CREATE OR REPLACE FUNCTION trigger_credit_deduct_on_call_complete()
RETURNS TRIGGER AS $$
DECLARE
  v_sms_cost INTEGER := 0;
  v_sms_actual INTEGER := 0;
  v_call_cost INTEGER := 0;
  v_call_actual INTEGER := 0;
  v_call_minutes INTEGER;
  v_total_billed INTEGER;
  v_total_actual INTEGER;
  v_sms_config RECORD;
  v_call_config RECORD;
  v_notes TEXT;
BEGIN
  -- Get SMS config
  SELECT cost_per_unit_cents, multiplier, minimum_charge_cents INTO v_sms_config
  FROM credit_service_config WHERE service_type = 'twilio_sms';

  -- Get call config
  SELECT cost_per_unit_cents, multiplier, minimum_charge_cents INTO v_call_config
  FROM credit_service_config WHERE service_type = 'vapi_call';

  -- Calculate SMS cost (only if SMS was actually sent)
  IF NEW.sms_status = 'sent' AND v_sms_config IS NOT NULL THEN
    v_sms_actual := v_sms_config.cost_per_unit_cents;
    v_sms_cost := GREATEST(
      CEIL(v_sms_config.cost_per_unit_cents * v_sms_config.multiplier),
      v_sms_config.minimum_charge_cents
    );
  END IF;

  -- Calculate call cost (based on duration in minutes, rounded up)
  IF NEW.call_duration_seconds > 0 AND v_call_config IS NOT NULL THEN
    v_call_minutes := CEIL(NEW.call_duration_seconds::DECIMAL / 60);
    v_call_actual := v_call_config.cost_per_unit_cents * v_call_minutes;
    v_call_cost := GREATEST(
      CEIL(v_call_config.cost_per_unit_cents * v_call_config.multiplier) * v_call_minutes,
      v_call_config.minimum_charge_cents
    );
  END IF;

  v_total_billed := v_sms_cost + v_call_cost;
  v_total_actual := v_sms_actual + v_call_actual;

  -- Skip if nothing to deduct
  IF v_total_billed = 0 THEN
    RETURN NEW;
  END IF;

  -- Build breakdown note
  v_notes := '';
  IF v_sms_cost > 0 THEN
    v_notes := 'SMS: $' || TO_CHAR(v_sms_cost / 100.0, 'FM990.00');
  END IF;
  IF v_call_cost > 0 THEN
    IF v_notes != '' THEN v_notes := v_notes || ' + '; END IF;
    v_notes := v_notes || 'Call ' || v_call_minutes || 'min: $' || TO_CHAR(v_call_cost / 100.0, 'FM990.00');
  END IF;

  -- Deduct combined cost
  PERFORM deduct_showroom_credit(
    NEW.showroom_id,
    v_total_billed,
    v_total_actual,
    v_total_billed,
    COALESCE(v_call_config.multiplier, v_sms_config.multiplier),
    'vapi_call',
    NEW.id,
    'voice_agent_log',
    v_notes
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER credit_deduct_on_call_complete
  AFTER UPDATE ON voice_agent_logs
  FOR EACH ROW
  WHEN (OLD.call_duration_seconds IS NULL AND NEW.call_duration_seconds IS NOT NULL)
  EXECUTE FUNCTION trigger_credit_deduct_on_call_complete();

-- ===========================================================================
-- 7. Trigger: Deduct on design request creation
-- ===========================================================================
CREATE OR REPLACE FUNCTION trigger_credit_deduct_on_design_request()
RETURNS TRIGGER AS $$
DECLARE
  v_config RECORD;
  v_billed INTEGER;
  v_actual INTEGER;
BEGIN
  SELECT cost_per_unit_cents, multiplier, minimum_charge_cents INTO v_config
  FROM credit_service_config WHERE service_type = 'design_request';

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
    'design_request',
    NEW.id,
    'design_request',
    'Design request'
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER credit_deduct_on_design_request
  AFTER INSERT ON design_requests
  FOR EACH ROW
  EXECUTE FUNCTION trigger_credit_deduct_on_design_request();

-- ===========================================================================
-- 8. Platform setting
-- ===========================================================================
INSERT INTO platform_settings (key, value, description, is_secret)
VALUES ('credit_block_on_zero', 'true', 'Block voice agent and design requests when credit balance is zero', false)
ON CONFLICT (key) DO NOTHING;
