-- ============================================================
-- EaseInn V1 — Seed Data (Demo Hotel & Initial Rooms)
-- ============================================================

DO $$
DECLARE
  v_prop_id uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_cat_std uuid := 'b0000000-0000-0000-0000-000000000001'::uuid;
  v_cat_del uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
  v_cat_sui uuid := 'b0000000-0000-0000-0000-000000000003'::uuid;
  v_guest1_id uuid := 'c0000000-0000-0000-0000-000000000001'::uuid;
  v_guest2_id uuid := 'c0000000-0000-0000-0000-000000000002'::uuid;
  v_room_102 uuid;
  v_room_104 uuid;
  v_stay1_id uuid;
  v_stay2_id uuid;
  v_bill1_id uuid;
  v_bill2_id uuid;
BEGIN
  -- 1. Insert Default Property if not exists
  INSERT INTO properties (
    id,
    name,
    address,
    city,
    state,
    pincode,
    phone,
    email,
    gst_number,
    currency,
    timezone
  ) VALUES (
    v_prop_id,
    'EaseInn Boutique & Suites',
    '88 MG Road, Indiranagar',
    'Bengaluru',
    'Karnataka',
    '560038',
    '+91 98765 43210',
    'frontdesk@easeinn.com',
    '29ABCDE1234F1Z5',
    'INR',
    'Asia/Kolkata'
  ) ON CONFLICT (id) DO NOTHING;

  -- 2. Insert Room Categories
  INSERT INTO room_categories (id, property_id, name, base_rate, max_occupancy, description)
  VALUES
    (v_cat_std, v_prop_id, 'Standard Room', 2200.00, 2, 'Cozy room with queen bed, ensuite bath, and city view'),
    (v_cat_del, v_prop_id, 'Deluxe Room', 3500.00, 3, 'Spacious room with king bed, workspace, and balcony'),
    (v_cat_sui, v_prop_id, 'Executive Suite', 5500.00, 4, 'Premium luxury suite with separate living room and mini bar')
  ON CONFLICT (property_id, name) DO NOTHING;

  -- 3. Insert Rooms (Floor 1 & Floor 2)
  -- Floor 1
  INSERT INTO rooms (property_id, category_id, room_number, floor, status)
  VALUES
    (v_prop_id, v_cat_std, '101', 1, 'vacant'),
    (v_prop_id, v_cat_std, '102', 1, 'occupied'),
    (v_prop_id, v_cat_del, '103', 1, 'vacant'),
    (v_prop_id, v_cat_del, '104', 1, 'occupied'),
    (v_prop_id, v_cat_sui, '105', 1, 'needs_cleaning'),
    (v_prop_id, v_cat_sui, '106', 1, 'vacant'),
  -- Floor 2
    (v_prop_id, v_cat_std, '201', 2, 'vacant'),
    (v_prop_id, v_cat_std, '202', 2, 'vacant'),
    (v_prop_id, v_cat_del, '203', 2, 'vacant'),
    (v_prop_id, v_cat_del, '204', 2, 'reserved'),
    (v_prop_id, v_cat_sui, '205', 2, 'vacant'),
    (v_prop_id, v_cat_sui, '206', 2, 'vacant')
  ON CONFLICT (property_id, room_number) DO NOTHING;

  -- 4. Insert Demo Guests
  INSERT INTO guests (
    id,
    property_id,
    full_name,
    phone,
    email,
    id_type,
    id_number_masked,
    date_of_birth,
    gender,
    address,
    pincode
  ) VALUES (
    v_guest1_id,
    v_prop_id,
    'Vikram Aditya Singh',
    '+91 98450 11223',
    'vikram.singh@example.com',
    'aadhaar',
    'XXXX-XXXX-8921',
    '1989-08-14',
    'male',
    'Flat 402, Sunshine Apartments, Sector 14, Gurugram',
    '122001'
  ), (
    v_guest2_id,
    v_prop_id,
    'Ananya Deshmukh',
    '+91 97112 33445',
    'ananya.d@example.com',
    'passport',
    'ZXXXX491',
    '1994-03-22',
    'female',
    '12 Prabhat Road, Shivaji Nagar, Pune',
    '411005'
  ) ON CONFLICT DO NOTHING;

  -- 5. Create active stays for occupied rooms
  SELECT id INTO v_room_102 FROM rooms WHERE property_id = v_prop_id AND room_number = '102';
  SELECT id INTO v_room_104 FROM rooms WHERE property_id = v_prop_id AND room_number = '104';

  IF v_room_102 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stays WHERE room_id = v_room_102 AND status = 'active') THEN
    INSERT INTO stays (
      property_id,
      guest_id,
      room_id,
      check_in_at,
      expected_checkout,
      num_guests,
      nightly_rate,
      status
    ) VALUES (
      v_prop_id,
      v_guest1_id,
      v_room_102,
      now() - interval '1 day',
      CURRENT_DATE + interval '2 days',
      1,
      2200.00,
      'active'
    ) RETURNING id INTO v_stay1_id;

    INSERT INTO bills (
      property_id, stay_id, bill_number, subtotal, total, amount_paid, outstanding, status
    ) VALUES (
      v_prop_id, v_stay1_id, 'INV-2026-0001', 6600.00, 6600.00, 2200.00, 4400.00, 'draft'
    ) RETURNING id INTO v_bill1_id;

    INSERT INTO bill_line_items (bill_id, description, quantity, unit_price, amount, item_type)
    VALUES (v_bill1_id, 'Room Stay (3 nights)', 3, 2200.00, 6600.00, 'room_charge');

    INSERT INTO payments (property_id, bill_id, amount, method, payment_type, reference)
    VALUES (v_prop_id, v_bill1_id, 2200.00, 'upi', 'advance', 'UPI-984501');
  END IF;

  IF v_room_104 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM stays WHERE room_id = v_room_104 AND status = 'active') THEN
    INSERT INTO stays (
      property_id,
      guest_id,
      room_id,
      check_in_at,
      expected_checkout,
      num_guests,
      nightly_rate,
      status
    ) VALUES (
      v_prop_id,
      v_guest2_id,
      v_room_104,
      now(),
      CURRENT_DATE + interval '1 day',
      2,
      3500.00,
      'active'
    ) RETURNING id INTO v_stay2_id;

    INSERT INTO bills (
      property_id, stay_id, bill_number, subtotal, total, amount_paid, outstanding, status
    ) VALUES (
      v_prop_id, v_stay2_id, 'INV-2026-0002', 3500.00, 3500.00, 3500.00, 0.00, 'draft'
    ) RETURNING id INTO v_bill2_id;

    INSERT INTO bill_line_items (bill_id, description, quantity, unit_price, amount, item_type)
    VALUES (v_bill2_id, 'Room Stay (1 night)', 1, 3500.00, 3500.00, 'room_charge');

    INSERT INTO payments (property_id, bill_id, amount, method, payment_type, reference)
    VALUES (v_prop_id, v_bill2_id, 3500.00, 'card', 'full', 'CARD-TXN-4819');
  END IF;

END $$;
