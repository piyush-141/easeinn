-- ==============================================================================
-- EaseInn V1 — Migration 00012: Incremental Realtime Sync & Publication Setup
-- ==============================================================================
-- 1. Ensure updated_at column exists with default now() on stays, bills,
--    payments, expenses, rooms, guests, bill_line_items.
-- 2. Create automatic trigger function to keep updated_at in sync on every UPDATE.
-- 3. Add all tables to supabase_realtime publication with REPLICA IDENTITY FULL
--    so delete/update events broadcast complete row state to all connected devices.
-- 4. Create composite indexes on (property_id, updated_at DESC) for lightning-fast
--    incremental sync queries.
-- ==============================================================================

-- 1. Generic trigger function for auto-updating updated_at
CREATE OR REPLACE FUNCTION set_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Add updated_at columns if not present
DO $$
BEGIN
  -- stays
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stays' AND column_name = 'updated_at') THEN
    ALTER TABLE stays ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;

  -- bills
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'bills' AND column_name = 'updated_at') THEN
    ALTER TABLE bills ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;

  -- payments
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'payments' AND column_name = 'updated_at') THEN
    ALTER TABLE payments ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;

  -- expenses
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'expenses' AND column_name = 'updated_at') THEN
    ALTER TABLE expenses ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;

  -- rooms
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'rooms' AND column_name = 'updated_at') THEN
    ALTER TABLE rooms ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;

  -- guests
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'guests' AND column_name = 'updated_at') THEN
    ALTER TABLE guests ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;

  -- bill_line_items
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'bill_line_items' AND column_name = 'updated_at') THEN
    ALTER TABLE bill_line_items ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;
END $$;

-- 3. Create triggers on all tables
DROP TRIGGER IF EXISTS trg_stays_updated_at ON stays;
CREATE TRIGGER trg_stays_updated_at
  BEFORE UPDATE ON stays
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at_column();

DROP TRIGGER IF EXISTS trg_bills_updated_at ON bills;
CREATE TRIGGER trg_bills_updated_at
  BEFORE UPDATE ON bills
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at_column();

DROP TRIGGER IF EXISTS trg_payments_updated_at ON payments;
CREATE TRIGGER trg_payments_updated_at
  BEFORE UPDATE ON payments
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at_column();

DROP TRIGGER IF EXISTS trg_expenses_updated_at ON expenses;
CREATE TRIGGER trg_expenses_updated_at
  BEFORE UPDATE ON expenses
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at_column();

DROP TRIGGER IF EXISTS trg_rooms_updated_at ON rooms;
CREATE TRIGGER trg_rooms_updated_at
  BEFORE UPDATE ON rooms
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at_column();

DROP TRIGGER IF EXISTS trg_guests_updated_at ON guests;
CREATE TRIGGER trg_guests_updated_at
  BEFORE UPDATE ON guests
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at_column();

DROP TRIGGER IF EXISTS trg_bill_line_items_updated_at ON bill_line_items;
CREATE TRIGGER trg_bill_line_items_updated_at
  BEFORE UPDATE ON bill_line_items
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at_column();

-- 4. Enable REPLICA IDENTITY FULL for all synced tables so Realtime payloads contain complete old and new records
ALTER TABLE rooms REPLICA IDENTITY FULL;
ALTER TABLE guests REPLICA IDENTITY FULL;
ALTER TABLE stays REPLICA IDENTITY FULL;
ALTER TABLE bills REPLICA IDENTITY FULL;
ALTER TABLE bill_line_items REPLICA IDENTITY FULL;
ALTER TABLE payments REPLICA IDENTITY FULL;
ALTER TABLE expenses REPLICA IDENTITY FULL;

-- 5. Add all tables to supabase_realtime publication
DO $$
BEGIN
  -- Check if supabase_realtime publication exists
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    -- Add tables if they are not already members
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE rooms, guests, stays, bills, bill_line_items, payments, expenses';
  END IF;
EXCEPTION
  WHEN duplicate_object THEN
    -- Table already in publication, ignore
    NULL;
END $$;

-- 6. Performance indexes for incremental cursor queries (WHERE property_id = ... AND updated_at > ...)
CREATE INDEX IF NOT EXISTS idx_rooms_property_updated ON rooms(property_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_guests_property_updated ON guests(property_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_stays_property_updated ON stays(property_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_bills_property_updated ON bills(property_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_property_updated ON payments(property_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_property_updated ON expenses(property_id, updated_at DESC);
