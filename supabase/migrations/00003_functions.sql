-- ============================================================
-- EaseInn V1 — Database Functions & Stored Procedures
-- ============================================================

-- ============================================================
-- 1. Check Room Availability
-- ============================================================
CREATE OR REPLACE FUNCTION check_room_availability(
  p_room_id uuid,
  p_check_in date,
  p_check_out date
)
RETURNS boolean AS $$
DECLARE
  v_conflicts integer;
BEGIN
  -- Check if room is currently in active stay
  SELECT COUNT(*) INTO v_conflicts
  FROM stays
  WHERE room_id = p_room_id
    AND status = 'active'
    AND (
      -- If active stay has expected checkout after requested checkin
      expected_checkout IS NULL OR expected_checkout >= p_check_in
    );

  IF v_conflicts > 0 THEN
    RETURN false;
  END IF;

  -- Check confirmed reservations overlapping with dates
  SELECT COUNT(*) INTO v_conflicts
  FROM reservations
  WHERE room_id = p_room_id
    AND status IN ('confirmed', 'checked_in')
    AND check_in_date < p_check_out
    AND check_out_date > p_check_in;

  RETURN (v_conflicts = 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 2. Generate Next Bill Number (e.g. INV-2026-0001)
-- ============================================================
CREATE OR REPLACE FUNCTION generate_bill_number(p_property_id uuid)
RETURNS text AS $$
DECLARE
  v_year text := to_char(now(), 'YYYY');
  v_count integer;
BEGIN
  SELECT COUNT(*) + 1 INTO v_count
  FROM bills
  WHERE property_id = p_property_id
    AND created_at >= date_trunc('year', now());

  RETURN 'INV-' || v_year || '-' || lpad(v_count::text, 4, '0');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 3. Create Check-In (Atomic Transaction)
-- ============================================================
CREATE OR REPLACE FUNCTION create_check_in(
  p_property_id     uuid,
  p_guest_id        uuid,
  p_room_id         uuid,
  p_expected_checkout date,
  p_nightly_rate    numeric,
  p_num_guests      integer DEFAULT 1,
  p_advance_amount  numeric DEFAULT 0,
  p_payment_method  text DEFAULT 'cash',
  p_payment_ref     text DEFAULT NULL,
  p_reservation_id  uuid DEFAULT NULL,
  p_checked_in_by   uuid DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
  v_stay_id uuid;
  v_bill_id uuid;
  v_bill_number text;
  v_est_nights integer;
  v_est_subtotal numeric;
  v_payment_id uuid;
BEGIN
  -- Verify room is not currently occupied
  IF EXISTS (SELECT 1 FROM stays WHERE room_id = p_room_id AND status = 'active') THEN
    RAISE EXCEPTION 'Room is already occupied by an active stay.';
  END IF;

  -- Calculate estimated nights and subtotal
  v_est_nights := GREATEST(1, (p_expected_checkout - CURRENT_DATE));
  v_est_subtotal := v_est_nights * p_nightly_rate;

  -- 1. Insert stay record
  INSERT INTO stays (
    property_id,
    reservation_id,
    guest_id,
    room_id,
    check_in_at,
    expected_checkout,
    num_guests,
    nightly_rate,
    status,
    checked_in_by
  ) VALUES (
    p_property_id,
    p_reservation_id,
    p_guest_id,
    p_room_id,
    now(),
    p_expected_checkout,
    p_num_guests,
    p_nightly_rate,
    'active',
    p_checked_in_by
  ) RETURNING id INTO v_stay_id;

  -- 2. Update room status to occupied
  UPDATE rooms
  SET status = 'occupied', updated_at = now()
  WHERE id = p_room_id;

  -- 3. If there was a reservation, update its status
  IF p_reservation_id IS NOT NULL THEN
    UPDATE reservations
    SET status = 'checked_in', updated_at = now()
    WHERE id = p_reservation_id;
  END IF;

  -- 4. Create initial bill
  v_bill_number := generate_bill_number(p_property_id);
  INSERT INTO bills (
    property_id,
    stay_id,
    bill_number,
    subtotal,
    tax_amount,
    discount_amount,
    total,
    amount_paid,
    outstanding,
    status
  ) VALUES (
    p_property_id,
    v_stay_id,
    v_bill_number,
    v_est_subtotal,
    0,
    0,
    v_est_subtotal,
    COALESCE(p_advance_amount, 0),
    GREATEST(0, v_est_subtotal - COALESCE(p_advance_amount, 0)),
    'draft'
  ) RETURNING id INTO v_bill_id;

  -- 5. Add initial room charge line item
  INSERT INTO bill_line_items (
    bill_id,
    description,
    quantity,
    unit_price,
    amount,
    item_type
  ) VALUES (
    v_bill_id,
    'Room Stay (' || v_est_nights || ' night' || CASE WHEN v_est_nights > 1 THEN 's' ELSE '' END || ')',
    v_est_nights,
    p_nightly_rate,
    v_est_subtotal,
    'room_charge'
  );

  -- 6. Record advance payment if provided
  IF p_advance_amount IS NOT NULL AND p_advance_amount > 0 THEN
    INSERT INTO payments (
      property_id,
      bill_id,
      amount,
      method,
      payment_type,
      reference,
      recorded_by
    ) VALUES (
      p_property_id,
      v_bill_id,
      p_advance_amount,
      p_payment_method,
      'advance',
      p_payment_ref,
      p_checked_in_by
    ) RETURNING id INTO v_payment_id;
  END IF;

  -- 7. Audit log
  INSERT INTO audit_events (
    property_id,
    user_id,
    action,
    entity_type,
    entity_id,
    details
  ) VALUES (
    p_property_id,
    p_checked_in_by,
    'guest_check_in',
    'stays',
    v_stay_id,
    jsonb_build_object(
      'room_id', p_room_id,
      'guest_id', p_guest_id,
      'bill_id', v_bill_id,
      'advance_paid', p_advance_amount
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'stay_id', v_stay_id,
    'bill_id', v_bill_id,
    'bill_number', v_bill_number
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 4. Complete Check-Out (Atomic Transaction)
-- ============================================================
CREATE OR REPLACE FUNCTION complete_checkout(
  p_stay_id         uuid,
  p_checked_out_by  uuid DEFAULT NULL,
  p_payment_amount  numeric DEFAULT 0,
  p_payment_method  text DEFAULT 'cash',
  p_payment_ref     text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
  v_stay record;
  v_bill record;
  v_actual_nights integer;
  v_actual_subtotal numeric;
  v_total_paid numeric;
  v_final_outstanding numeric;
BEGIN
  -- Get active stay
  SELECT * INTO v_stay
  FROM stays
  WHERE id = p_stay_id AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active stay not found for id %', p_stay_id;
  END IF;

  -- Calculate actual nights stayed
  v_actual_nights := GREATEST(1, CURRENT_DATE - v_stay.check_in_at::date);
  v_actual_subtotal := v_actual_nights * v_stay.nightly_rate;

  -- Get associated bill
  SELECT * INTO v_bill
  FROM bills
  WHERE stay_id = p_stay_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    -- Update bill room charge line item if nights changed
    UPDATE bill_line_items
    SET quantity = v_actual_nights,
        amount = v_actual_subtotal,
        description = 'Room Stay (' || v_actual_nights || ' night' || CASE WHEN v_actual_nights > 1 THEN 's' ELSE '' END || ')'
    WHERE bill_id = v_bill.id AND item_type = 'room_charge';

    -- Recalculate bill total (subtotal of all items)
    SELECT COALESCE(SUM(amount), 0) INTO v_actual_subtotal
    FROM bill_line_items
    WHERE bill_id = v_bill.id;

    -- Record checkout payment if given
    IF p_payment_amount IS NOT NULL AND p_payment_amount > 0 THEN
      INSERT INTO payments (
        property_id,
        bill_id,
        amount,
        method,
        payment_type,
        reference,
        recorded_by
      ) VALUES (
        v_stay.property_id,
        v_bill.id,
        p_payment_amount,
        p_payment_method,
        'full',
        p_payment_ref,
        p_checked_out_by
      );
    END IF;

    -- Total paid across non-void payments
    SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
    FROM payments
    WHERE bill_id = v_bill.id AND is_void = false;

    v_final_outstanding := GREATEST(0, v_actual_subtotal - v_total_paid);

    -- Finalize bill
    UPDATE bills
    SET subtotal = v_actual_subtotal,
        total = v_actual_subtotal,
        amount_paid = v_total_paid,
        outstanding = v_final_outstanding,
        status = 'finalized',
        finalized_at = now(),
        updated_at = now()
    WHERE id = v_bill.id;
  END IF;

  -- Update stay record
  UPDATE stays
  SET status = 'checked_out',
      check_out_at = now(),
      checked_out_by = p_checked_out_by
  WHERE id = p_stay_id;

  -- Update room status to 'needs_cleaning'
  UPDATE rooms
  SET status = 'needs_cleaning',
      updated_at = now()
  WHERE id = v_stay.room_id;

  -- Audit log
  INSERT INTO audit_events (
    property_id,
    user_id,
    action,
    entity_type,
    entity_id,
    details
  ) VALUES (
    v_stay.property_id,
    p_checked_out_by,
    'guest_check_out',
    'stays',
    p_stay_id,
    jsonb_build_object(
      'room_id', v_stay.room_id,
      'guest_id', v_stay.guest_id,
      'bill_id', v_bill.id,
      'nights', v_actual_nights,
      'final_outstanding', v_final_outstanding
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'stay_id', p_stay_id,
    'bill_id', v_bill.id,
    'actual_nights', v_actual_nights,
    'total_amount', v_actual_subtotal,
    'outstanding', v_final_outstanding
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 5. Record Payment (Atomic Transaction)
-- ============================================================
CREATE OR REPLACE FUNCTION record_payment(
  p_property_id    uuid,
  p_bill_id        uuid,
  p_amount         numeric,
  p_method         text,
  p_payment_type   text DEFAULT 'partial',
  p_reference      text DEFAULT NULL,
  p_recorded_by    uuid DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
  v_payment_id uuid;
  v_bill record;
  v_new_paid numeric;
  v_new_outstanding numeric;
BEGIN
  SELECT * INTO v_bill FROM bills WHERE id = p_bill_id AND property_id = p_property_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bill not found.';
  END IF;

  INSERT INTO payments (
    property_id,
    bill_id,
    amount,
    method,
    payment_type,
    reference,
    recorded_by
  ) VALUES (
    p_property_id,
    p_bill_id,
    p_amount,
    p_method,
    p_payment_type,
    p_reference,
    p_recorded_by
  ) RETURNING id INTO v_payment_id;

  -- Recalculate bill payments
  SELECT COALESCE(SUM(amount), 0) INTO v_new_paid
  FROM payments
  WHERE bill_id = p_bill_id AND is_void = false;

  v_new_outstanding := GREATEST(0, v_bill.total - v_new_paid);

  UPDATE bills
  SET amount_paid = v_new_paid,
      outstanding = v_new_outstanding,
      updated_at = now()
  WHERE id = p_bill_id;

  RETURN jsonb_build_object(
    'success', true,
    'payment_id', v_payment_id,
    'amount_paid', v_new_paid,
    'outstanding', v_new_outstanding
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 6. Get Dashboard Stats
-- ============================================================
CREATE OR REPLACE FUNCTION get_dashboard_stats(p_property_id uuid)
RETURNS jsonb AS $$
DECLARE
  v_total_rooms integer := 0;
  v_vacant_rooms integer := 0;
  v_occupied_rooms integer := 0;
  v_reserved_rooms integer := 0;
  v_cleaning_rooms integer := 0;
  v_today_arrivals integer := 0;
  v_today_departures integer := 0;
  v_active_guests integer := 0;
  v_revenue_today numeric := 0;
  v_occupancy_rate numeric := 0;
BEGIN
  -- Room counts
  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE status = 'vacant'),
    COUNT(*) FILTER (WHERE status = 'occupied'),
    COUNT(*) FILTER (WHERE status = 'reserved'),
    COUNT(*) FILTER (WHERE status = 'needs_cleaning')
  INTO
    v_total_rooms,
    v_vacant_rooms,
    v_occupied_rooms,
    v_reserved_rooms,
    v_cleaning_rooms
  FROM rooms
  WHERE property_id = p_property_id AND is_active = true;

  -- Occupancy rate
  IF v_total_rooms > 0 THEN
    v_occupancy_rate := ROUND((v_occupied_rooms::numeric / v_total_rooms::numeric) * 100, 1);
  END IF;

  -- Today's arrivals (reservations scheduled for check_in today OR stays checked in today)
  SELECT COUNT(*) INTO v_today_arrivals
  FROM stays
  WHERE property_id = p_property_id
    AND check_in_at::date = CURRENT_DATE;

  -- Today's departures (expected checkout today)
  SELECT COUNT(*) INTO v_today_departures
  FROM stays
  WHERE property_id = p_property_id
    AND status = 'active'
    AND expected_checkout = CURRENT_DATE;

  -- Active guests
  SELECT COALESCE(SUM(num_guests), 0) INTO v_active_guests
  FROM stays
  WHERE property_id = p_property_id AND status = 'active';

  -- Revenue collected today
  SELECT COALESCE(SUM(amount), 0) INTO v_revenue_today
  FROM payments
  WHERE property_id = p_property_id
    AND is_void = false
    AND recorded_at::date = CURRENT_DATE;

  RETURN jsonb_build_object(
    'total_rooms', v_total_rooms,
    'vacant_rooms', v_vacant_rooms,
    'occupied_rooms', v_occupied_rooms,
    'reserved_rooms', v_reserved_rooms,
    'cleaning_rooms', v_cleaning_rooms,
    'occupancy_rate', v_occupancy_rate,
    'today_arrivals', v_today_arrivals,
    'today_departures', v_today_departures,
    'active_guests', v_active_guests,
    'revenue_today', v_revenue_today
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
