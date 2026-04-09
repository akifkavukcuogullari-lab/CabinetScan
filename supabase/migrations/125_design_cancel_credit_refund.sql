-- Refund credit when a design request is canceled (deleted)
-- Looks up the original debit transaction and refunds the billed amount

CREATE OR REPLACE FUNCTION trigger_credit_refund_on_design_cancel()
RETURNS TRIGGER AS $$
DECLARE
  v_txn RECORD;
BEGIN
  -- Find the original debit transaction for this design request
  SELECT billed_cost_cents, showroom_id INTO v_txn
  FROM showroom_credit_transactions
  WHERE reference_id = OLD.id
    AND reference_type = 'design_request'
    AND type = 'debit'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_txn IS NOT NULL AND v_txn.billed_cost_cents > 0 THEN
    -- Refund by adding credits back
    PERFORM add_showroom_credit(
      OLD.showroom_id,
      v_txn.billed_cost_cents,
      'refund',
      NULL,
      'Design request canceled — credit refunded'
    );
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER credit_refund_on_design_cancel
  BEFORE DELETE ON design_requests
  FOR EACH ROW
  EXECUTE FUNCTION trigger_credit_refund_on_design_cancel();
