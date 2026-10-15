-- ============================================================
-- EaseInn V1 — Row Level Security (RLS) Policies
-- ============================================================

-- Helper function: get current user's property_id
CREATE OR REPLACE FUNCTION current_user_property_id()
RETURNS uuid AS $$
  SELECT property_id FROM user_profiles WHERE id = auth.uid() AND is_active = true;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper function: get current user's role ('admin' or 'receptionist')
CREATE OR REPLACE FUNCTION current_user_role()
RETURNS text AS $$
  SELECT role FROM user_profiles WHERE id = auth.uid() AND is_active = true;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper function: check if user is active staff of property
CREATE OR REPLACE FUNCTION is_property_staff(check_property_id uuid)
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_profiles
    WHERE id = auth.uid()
      AND property_id = check_property_id
      AND is_active = true
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ============================================================
-- Enable RLS on all tables
-- ============================================================
ALTER TABLE properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE guests ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE stays ENABLE ROW LEVEL SECURITY;
ALTER TABLE stay_guests ENABLE ROW LEVEL SECURITY;
ALTER TABLE bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE bill_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 1. PROPERTIES
-- ============================================================
CREATE POLICY "Users can view assigned property"
  ON properties FOR SELECT
  USING (id = current_user_property_id());

CREATE POLICY "Admins can update their property"
  ON properties FOR UPDATE
  USING (id = current_user_property_id() AND current_user_role() = 'admin')
  WITH CHECK (id = current_user_property_id() AND current_user_role() = 'admin');

CREATE POLICY "Authenticated users can create a new property"
  ON properties FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- ============================================================
-- 2. USER_PROFILES
-- ============================================================
CREATE POLICY "Users can view own profile or profiles in same property"
  ON user_profiles FOR SELECT
  USING (
    id = auth.uid()
    OR (property_id IS NOT NULL AND property_id = current_user_property_id())
  );

CREATE POLICY "Users can update own profile"
  ON user_profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE POLICY "Admins can insert or manage profiles for their property"
  ON user_profiles FOR INSERT
  WITH CHECK (
    id = auth.uid() -- Allows first-time profile creation upon signup
    OR (property_id = current_user_property_id() AND current_user_role() = 'admin')
  );

-- ============================================================
-- 3. ROOM CATEGORIES
-- ============================================================
CREATE POLICY "Staff can view room categories"
  ON room_categories FOR SELECT
  USING (property_id = current_user_property_id());

CREATE POLICY "Admins can manage room categories"
  ON room_categories FOR ALL
  USING (property_id = current_user_property_id() AND current_user_role() = 'admin')
  WITH CHECK (property_id = current_user_property_id() AND current_user_role() = 'admin');

-- ============================================================
-- 4. ROOMS
-- ============================================================
CREATE POLICY "Staff can view rooms"
  ON rooms FOR SELECT
  USING (property_id = current_user_property_id());

CREATE POLICY "Staff can update room status"
  ON rooms FOR UPDATE
  USING (property_id = current_user_property_id())
  WITH CHECK (property_id = current_user_property_id());

CREATE POLICY "Admins can manage rooms"
  ON rooms FOR ALL
  USING (property_id = current_user_property_id() AND current_user_role() = 'admin')
  WITH CHECK (property_id = current_user_property_id() AND current_user_role() = 'admin');

-- ============================================================
-- 5. GUESTS
-- ============================================================
CREATE POLICY "Staff can view guests in their property"
  ON guests FOR SELECT
  USING (property_id = current_user_property_id());

CREATE POLICY "Staff can insert guests"
  ON guests FOR INSERT
  WITH CHECK (property_id = current_user_property_id());

CREATE POLICY "Staff can update guests"
  ON guests FOR UPDATE
  USING (property_id = current_user_property_id())
  WITH CHECK (property_id = current_user_property_id());

-- ============================================================
-- 6. RESERVATIONS
-- ============================================================
CREATE POLICY "Staff can view reservations"
  ON reservations FOR SELECT
  USING (property_id = current_user_property_id());

CREATE POLICY "Staff can insert reservations"
  ON reservations FOR INSERT
  WITH CHECK (property_id = current_user_property_id());

CREATE POLICY "Staff can update reservations"
  ON reservations FOR UPDATE
  USING (property_id = current_user_property_id())
  WITH CHECK (property_id = current_user_property_id());

-- ============================================================
-- 7. STAYS
-- ============================================================
CREATE POLICY "Staff can view stays"
  ON stays FOR SELECT
  USING (property_id = current_user_property_id());

CREATE POLICY "Staff can insert stays"
  ON stays FOR INSERT
  WITH CHECK (property_id = current_user_property_id());

CREATE POLICY "Staff can update stays"
  ON stays FOR UPDATE
  USING (property_id = current_user_property_id())
  WITH CHECK (property_id = current_user_property_id());

-- ============================================================
-- 8. STAY_GUESTS
-- ============================================================
CREATE POLICY "Staff can view stay_guests"
  ON stay_guests FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM stays
      WHERE stays.id = stay_guests.stay_id
        AND stays.property_id = current_user_property_id()
    )
  );

CREATE POLICY "Staff can insert stay_guests"
  ON stay_guests FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM stays
      WHERE stays.id = stay_guests.stay_id
        AND stays.property_id = current_user_property_id()
    )
  );

-- ============================================================
-- 9. BILLS
-- ============================================================
CREATE POLICY "Staff can view bills"
  ON bills FOR SELECT
  USING (property_id = current_user_property_id());

CREATE POLICY "Staff can insert bills"
  ON bills FOR INSERT
  WITH CHECK (property_id = current_user_property_id());

CREATE POLICY "Staff can update bills"
  ON bills FOR UPDATE
  USING (property_id = current_user_property_id())
  WITH CHECK (property_id = current_user_property_id());

-- ============================================================
-- 10. BILL LINE ITEMS
-- ============================================================
CREATE POLICY "Staff can view bill line items"
  ON bill_line_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM bills
      WHERE bills.id = bill_line_items.bill_id
        AND bills.property_id = current_user_property_id()
    )
  );

CREATE POLICY "Staff can manage bill line items"
  ON bill_line_items FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM bills
      WHERE bills.id = bill_line_items.bill_id
        AND bills.property_id = current_user_property_id()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM bills
      WHERE bills.id = bill_line_items.bill_id
        AND bills.property_id = current_user_property_id()
    )
  );

-- ============================================================
-- 11. PAYMENTS
-- ============================================================
CREATE POLICY "Staff can view payments"
  ON payments FOR SELECT
  USING (property_id = current_user_property_id());

CREATE POLICY "Staff can insert payments"
  ON payments FOR INSERT
  WITH CHECK (property_id = current_user_property_id());

-- Note: Payments are immutable by design; voids update is_void, void_reason, voided_by, voided_at
CREATE POLICY "Staff can void payments"
  ON payments FOR UPDATE
  USING (property_id = current_user_property_id())
  WITH CHECK (property_id = current_user_property_id());

-- ============================================================
-- 12. AUDIT EVENTS
-- ============================================================
CREATE POLICY "Staff can view audit events"
  ON audit_events FOR SELECT
  USING (property_id = current_user_property_id());

CREATE POLICY "Staff can insert audit events"
  ON audit_events FOR INSERT
  WITH CHECK (property_id = current_user_property_id());
