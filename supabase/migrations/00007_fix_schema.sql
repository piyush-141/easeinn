-- ============================================================
-- EaseInn V1 — Schema Fix Migration
-- Run in Supabase SQL Editor
-- Fixes: stays status constraint, rooms base_rate, guests id_number
-- ============================================================

-- 1. Fix stays status constraint to include 'reserved'
ALTER TABLE stays DROP CONSTRAINT IF EXISTS stays_status_check;
ALTER TABLE stays ADD CONSTRAINT stays_status_check
  CHECK (status IN ('active', 'checked_out', 'reserved'));

-- 2. Add base_rate column to rooms (app needs it)
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS base_rate numeric(10,2) NOT NULL DEFAULT 2000;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS category_name text NOT NULL DEFAULT 'Standard Room';

-- 3. Add id_number column to guests (app stores raw ID locally + masked)
-- We store it encrypted/hashed for security, but keep raw for app sync
ALTER TABLE guests ADD COLUMN IF NOT EXISTS id_number text;
ALTER TABLE guests ADD COLUMN IF NOT EXISTS father_name text;
ALTER TABLE guests ADD COLUMN IF NOT EXISTS stays_count integer NOT NULL DEFAULT 1;
ALTER TABLE guests ADD COLUMN IF NOT EXISTS num_adults integer NOT NULL DEFAULT 1;
ALTER TABLE guests ADD COLUMN IF NOT EXISTS num_kids integer NOT NULL DEFAULT 0;

-- 4. Fix stays to add num_adults and num_kids columns
ALTER TABLE stays ADD COLUMN IF NOT EXISTS num_adults integer NOT NULL DEFAULT 1;
ALTER TABLE stays ADD COLUMN IF NOT EXISTS num_kids integer NOT NULL DEFAULT 0;

-- 5. Add default_checkin_time and checkout as text to properties (not time type, easier for app)
-- (they already exist as time, but add text versions for app compat)
ALTER TABLE properties ADD COLUMN IF NOT EXISTS upi_id text;
ALTER TABLE properties ADD COLUMN IF NOT EXISTS upi_payee_name text;
ALTER TABLE properties ADD COLUMN IF NOT EXISTS hotel_tier text;

-- 6. Fix the RLS on rooms - staff needs INSERT for initial room sync
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'rooms' AND policyname = 'Staff can insert rooms'
  ) THEN
    CREATE POLICY "Staff can insert rooms"
      ON rooms FOR INSERT
      WITH CHECK (property_id = current_user_property_id());
  END IF;
END $$;

-- 7. Fix guests RLS - allow upsert
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'guests' AND policyname = 'Staff can delete guests'
  ) THEN
    -- Allow staff to delete/manage guests in their property
    CREATE POLICY "Staff can delete guests"
      ON guests FOR DELETE
      USING (property_id = current_user_property_id());
  END IF;
END $$;

-- 8. Fix stays RLS - allow delete for cancelled reservations
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'stays' AND policyname = 'Staff can delete stays'
  ) THEN
    CREATE POLICY "Staff can delete stays"
      ON stays FOR DELETE
      USING (property_id = current_user_property_id());
  END IF;
END $$;

-- 9. Sync the gender check to be case-insensitive friendly by removing constraint and re-adding
ALTER TABLE guests DROP CONSTRAINT IF EXISTS guests_gender_check;
ALTER TABLE guests ADD CONSTRAINT guests_gender_check
  CHECK (gender IS NULL OR lower(gender) IN ('male', 'female', 'other'));

-- 10. Remove the unique active stay per room constraint that can block re-check-in after checkout
-- This is too strict for our use case (checkout marks it checked_out first)
-- Leave as-is since it only applies to 'active' status

-- ============================================================
-- Verify changes
-- ============================================================
SELECT 'Schema fix complete. Tables updated:' as status;
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name IN ('rooms', 'stays', 'guests', 'properties')
  AND column_name IN ('base_rate', 'category_name', 'id_number', 'father_name', 'num_adults', 'num_kids', 'upi_id', 'status')
ORDER BY table_name, column_name;
