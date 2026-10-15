-- ============================================================
-- EaseInn V1 — Initial Schema
-- ============================================================
-- Run this against your Supabase project's SQL Editor
-- or via supabase migrations.

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. PROPERTIES (Hotels)
-- ============================================================
CREATE TABLE properties (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name            text NOT NULL,
  address         text,
  city            text,
  state           text,
  pincode         text,
  phone           text,
  email           text,
  gst_number      text,
  currency        text NOT NULL DEFAULT 'INR',
  timezone        text NOT NULL DEFAULT 'Asia/Kolkata',
  default_checkin_time   time NOT NULL DEFAULT '12:00',
  default_checkout_time  time NOT NULL DEFAULT '11:00',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 2. USER PROFILES
-- ============================================================
CREATE TABLE user_profiles (
  id              uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  property_id     uuid REFERENCES properties(id) ON DELETE SET NULL,
  full_name       text NOT NULL,
  role            text NOT NULL DEFAULT 'receptionist'
                  CHECK (role IN ('admin', 'receptionist')),
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_user_profiles_property ON user_profiles(property_id);

-- ============================================================
-- 3. ROOM CATEGORIES
-- ============================================================
CREATE TABLE room_categories (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id     uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  name            text NOT NULL,
  base_rate       numeric(10,2) NOT NULL,
  max_occupancy   integer NOT NULL DEFAULT 2,
  description     text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE(property_id, name)
);

CREATE INDEX idx_room_categories_property ON room_categories(property_id);

-- ============================================================
-- 4. ROOMS
-- ============================================================
CREATE TABLE rooms (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id     uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  category_id     uuid REFERENCES room_categories(id) ON DELETE SET NULL,
  room_number     text NOT NULL,
  floor           integer NOT NULL DEFAULT 1,
  status          text NOT NULL DEFAULT 'vacant'
                  CHECK (status IN ('vacant', 'occupied', 'reserved', 'maintenance', 'needs_cleaning')),
  rate_override   numeric(10,2),
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE(property_id, room_number)
);

CREATE INDEX idx_rooms_property ON rooms(property_id);
CREATE INDEX idx_rooms_status ON rooms(property_id, status);
CREATE INDEX idx_rooms_floor ON rooms(property_id, floor);

-- ============================================================
-- 5. GUESTS
-- ============================================================
CREATE TABLE guests (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id     uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  full_name       text NOT NULL,
  phone           text,
  email           text,
  id_type         text CHECK (id_type IN ('aadhaar', 'pan', 'passport', 'voter_id', 'driving_license', 'other')),
  id_number_hash  text,
  id_number_masked text,
  date_of_birth   date,
  gender          text CHECK (gender IN ('male', 'female', 'other')),
  address         text,
  pincode         text,
  notes           text,
  id_document_path text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_guests_property ON guests(property_id);
CREATE INDEX idx_guests_phone ON guests(property_id, phone);
CREATE INDEX idx_guests_name ON guests(property_id, full_name);
CREATE INDEX idx_guests_id_hash ON guests(property_id, id_number_hash);

-- ============================================================
-- 6. RESERVATIONS
-- ============================================================
CREATE TABLE reservations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id     uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  guest_id        uuid NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
  room_id         uuid REFERENCES rooms(id) ON DELETE SET NULL,
  category_id     uuid REFERENCES room_categories(id) ON DELETE SET NULL,
  check_in_date   date NOT NULL,
  check_out_date  date NOT NULL,
  num_guests      integer NOT NULL DEFAULT 1,
  quoted_rate     numeric(10,2),
  status          text NOT NULL DEFAULT 'confirmed'
                  CHECK (status IN ('confirmed', 'checked_in', 'completed', 'cancelled', 'no_show')),
  source          text DEFAULT 'walk_in'
                  CHECK (source IN ('walk_in', 'phone', 'online', 'ota', 'other')),
  remarks         text,
  created_by      uuid REFERENCES user_profiles(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT valid_dates CHECK (check_out_date > check_in_date)
);

CREATE INDEX idx_reservations_property ON reservations(property_id);
CREATE INDEX idx_reservations_guest ON reservations(guest_id);
CREATE INDEX idx_reservations_room ON reservations(room_id);
CREATE INDEX idx_reservations_dates ON reservations(property_id, check_in_date, check_out_date);
CREATE INDEX idx_reservations_status ON reservations(property_id, status);

-- ============================================================
-- 7. STAYS
-- ============================================================
CREATE TABLE stays (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id     uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  reservation_id  uuid REFERENCES reservations(id) ON DELETE SET NULL,
  guest_id        uuid NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
  room_id         uuid NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  check_in_at     timestamptz NOT NULL DEFAULT now(),
  check_out_at    timestamptz,
  expected_checkout date,
  num_guests      integer NOT NULL DEFAULT 1,
  nightly_rate    numeric(10,2) NOT NULL,
  status          text NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active', 'checked_out')),
  checked_in_by   uuid REFERENCES user_profiles(id) ON DELETE SET NULL,
  checked_out_by  uuid REFERENCES user_profiles(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Prevent double-booking: only one active stay per room at a time
CREATE UNIQUE INDEX idx_one_active_stay_per_room
  ON stays (room_id) WHERE status = 'active';

CREATE INDEX idx_stays_property ON stays(property_id);
CREATE INDEX idx_stays_guest ON stays(guest_id);
CREATE INDEX idx_stays_room ON stays(room_id);
CREATE INDEX idx_stays_status ON stays(property_id, status);
CREATE INDEX idx_stays_checkin ON stays(property_id, check_in_at);

-- ============================================================
-- 8. STAY_GUESTS (additional guests per stay)
-- ============================================================
CREATE TABLE stay_guests (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stay_id         uuid NOT NULL REFERENCES stays(id) ON DELETE CASCADE,
  guest_id        uuid NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE(stay_id, guest_id)
);

-- ============================================================
-- 9. BILLS
-- ============================================================
CREATE TABLE bills (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id     uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  stay_id         uuid NOT NULL REFERENCES stays(id) ON DELETE CASCADE,
  bill_number     text,
  subtotal        numeric(10,2) NOT NULL DEFAULT 0,
  tax_amount      numeric(10,2) NOT NULL DEFAULT 0,
  discount_amount numeric(10,2) NOT NULL DEFAULT 0,
  total           numeric(10,2) NOT NULL DEFAULT 0,
  amount_paid     numeric(10,2) NOT NULL DEFAULT 0,
  outstanding     numeric(10,2) NOT NULL DEFAULT 0,
  status          text NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft', 'finalized', 'void')),
  finalized_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_bills_property ON bills(property_id);
CREATE INDEX idx_bills_stay ON bills(stay_id);

-- ============================================================
-- 10. BILL LINE ITEMS
-- ============================================================
CREATE TABLE bill_line_items (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bill_id         uuid NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
  description     text NOT NULL,
  quantity        numeric(10,2) NOT NULL DEFAULT 1,
  unit_price      numeric(10,2) NOT NULL,
  amount          numeric(10,2) NOT NULL,
  item_type       text NOT NULL DEFAULT 'room_charge'
                  CHECK (item_type IN ('room_charge', 'extra_charge', 'tax', 'discount')),
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_bill_line_items_bill ON bill_line_items(bill_id);

-- ============================================================
-- 11. PAYMENTS
-- ============================================================
CREATE TABLE payments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id     uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  bill_id         uuid NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
  amount          numeric(10,2) NOT NULL,
  method          text NOT NULL
                  CHECK (method IN ('cash', 'upi', 'card', 'bank_transfer', 'other')),
  payment_type    text NOT NULL DEFAULT 'full'
                  CHECK (payment_type IN ('advance', 'partial', 'full', 'refund')),
  reference       text,
  recorded_by     uuid REFERENCES user_profiles(id) ON DELETE SET NULL,
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  is_void         boolean NOT NULL DEFAULT false,
  void_reason     text,
  voided_by       uuid REFERENCES user_profiles(id) ON DELETE SET NULL,
  voided_at       timestamptz
);

CREATE INDEX idx_payments_property ON payments(property_id);
CREATE INDEX idx_payments_bill ON payments(bill_id);

-- ============================================================
-- 12. AUDIT EVENTS
-- ============================================================
CREATE TABLE audit_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id     uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  user_id         uuid REFERENCES user_profiles(id) ON DELETE SET NULL,
  action          text NOT NULL,
  entity_type     text,
  entity_id       uuid,
  details         jsonb DEFAULT '{}',
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_property ON audit_events(property_id);
CREATE INDEX idx_audit_entity ON audit_events(entity_type, entity_id);
CREATE INDEX idx_audit_created ON audit_events(property_id, created_at DESC);

-- ============================================================
-- Auto-update updated_at triggers
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_properties_updated_at
  BEFORE UPDATE ON properties
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_user_profiles_updated_at
  BEFORE UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_room_categories_updated_at
  BEFORE UPDATE ON room_categories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_rooms_updated_at
  BEFORE UPDATE ON rooms
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_guests_updated_at
  BEFORE UPDATE ON guests
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_reservations_updated_at
  BEFORE UPDATE ON reservations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_bills_updated_at
  BEFORE UPDATE ON bills
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
