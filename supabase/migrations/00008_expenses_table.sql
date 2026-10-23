-- ============================================================
-- EaseInn — Expenses Table Migration
-- Run in Supabase SQL Editor
-- ============================================================

-- 1. Create expenses table
CREATE TABLE IF NOT EXISTS expenses (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  amount      numeric(12,2) NOT NULL CHECK (amount > 0),
  category    text NOT NULL DEFAULT 'other'
                CHECK (category IN ('supplies','maintenance','salary','utilities',
                                    'food_beverage','housekeeping','marketing','other')),
  payment_method text NOT NULL DEFAULT 'cash'
                CHECK (payment_method IN ('cash','upi','card','bank_transfer')),
  reference   text,
  notes       text,
  added_by    text NOT NULL DEFAULT '',
  recorded_at timestamptz NOT NULL DEFAULT now(),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- 2. Index for fast property + date queries
CREATE INDEX IF NOT EXISTS idx_expenses_property_date
  ON expenses(property_id, recorded_at DESC);

-- 3. RLS Policies
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "expenses_select_own" ON expenses;
CREATE POLICY "expenses_select_own" ON expenses
  FOR SELECT USING (
    property_id IN (
      SELECT property_id FROM user_profiles WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "expenses_insert_own" ON expenses;
CREATE POLICY "expenses_insert_own" ON expenses
  FOR INSERT WITH CHECK (
    property_id IN (
      SELECT property_id FROM user_profiles WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "expenses_update_own" ON expenses;
CREATE POLICY "expenses_update_own" ON expenses
  FOR UPDATE USING (
    property_id IN (
      SELECT property_id FROM user_profiles WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "expenses_delete_own" ON expenses;
CREATE POLICY "expenses_delete_own" ON expenses
  FOR DELETE USING (
    property_id IN (
      SELECT property_id FROM user_profiles WHERE id = auth.uid()
    )
  );
