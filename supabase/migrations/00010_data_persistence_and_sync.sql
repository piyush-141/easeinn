-- ============================================================
-- EaseInn V1 — Migration 00010: Data Persistence & Sync Fixes
-- ============================================================
-- 1. Update bills status constraint to support 'reserved'
-- 2. Ensure RLS policies on bills, bill_line_items, payments, stays, rooms allow staff full CRUD
-- 3. Ensure ON CONFLICT support on primary keys and property scoping
-- 4. No seed data
-- ============================================================

-- 1. Allow 'reserved' on bills.status
ALTER TABLE bills DROP CONSTRAINT IF EXISTS bills_status_check;
ALTER TABLE bills ADD CONSTRAINT bills_status_check
  CHECK (status IN ('draft', 'finalized', 'void', 'reserved'));

-- 2. Ensure bills RLS supports INSERT, UPDATE, DELETE, and SELECT for staff
ALTER TABLE bills ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff can view bills" ON bills;
CREATE POLICY "Staff can view bills" ON bills
  FOR SELECT USING (
    property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "Staff can insert bills" ON bills;
CREATE POLICY "Staff can insert bills" ON bills
  FOR INSERT WITH CHECK (
    property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "Staff can update bills" ON bills;
CREATE POLICY "Staff can update bills" ON bills
  FOR UPDATE USING (
    property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
  ) WITH CHECK (
    property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "Staff can delete bills" ON bills;
CREATE POLICY "Staff can delete bills" ON bills
  FOR DELETE USING (
    property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
  );

-- 3. Ensure bill_line_items RLS allows full CRUD
ALTER TABLE bill_line_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff can view bill line items" ON bill_line_items;
CREATE POLICY "Staff can view bill line items" ON bill_line_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM bills
      WHERE bills.id = bill_line_items.bill_id
        AND bills.property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Staff can manage bill line items" ON bill_line_items;
CREATE POLICY "Staff can manage bill line items" ON bill_line_items
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM bills
      WHERE bills.id = bill_line_items.bill_id
        AND bills.property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM bills
      WHERE bills.id = bill_line_items.bill_id
        AND bills.property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
    )
  );

-- 4. Ensure payments RLS supports full CRUD
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff can view payments" ON payments;
CREATE POLICY "Staff can view payments" ON payments
  FOR SELECT USING (
    property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "Staff can insert payments" ON payments;
CREATE POLICY "Staff can insert payments" ON payments
  FOR INSERT WITH CHECK (
    property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "Staff can update payments" ON payments;
CREATE POLICY "Staff can update payments" ON payments
  FOR UPDATE USING (
    property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
  ) WITH CHECK (
    property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "Staff can delete payments" ON payments;
CREATE POLICY "Staff can delete payments" ON payments
  FOR DELETE USING (
    property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
  );

-- 5. Ensure rooms allows DELETE by staff
DROP POLICY IF EXISTS "Staff can delete rooms" ON rooms;
CREATE POLICY "Staff can delete rooms" ON rooms
  FOR DELETE USING (
    property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
  );

-- 6. Ensure stay_guests table has proper RLS for co-guest linking
ALTER TABLE stay_guests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff can view stay_guests" ON stay_guests;
CREATE POLICY "Staff can view stay_guests" ON stay_guests
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM stays
      WHERE stays.id = stay_guests.stay_id
        AND stays.property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Staff can manage stay_guests" ON stay_guests;
CREATE POLICY "Staff can manage stay_guests" ON stay_guests
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM stays
      WHERE stays.id = stay_guests.stay_id
        AND stays.property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM stays
      WHERE stays.id = stay_guests.stay_id
        AND stays.property_id IN (SELECT property_id FROM user_profiles WHERE id = auth.uid())
    )
  );

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_bills_property_created ON bills(property_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_property_recorded ON payments(property_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_stays_property_checkin ON stays(property_id, check_in_at DESC);
CREATE INDEX IF NOT EXISTS idx_guests_property_created ON guests(property_id, created_at DESC);
