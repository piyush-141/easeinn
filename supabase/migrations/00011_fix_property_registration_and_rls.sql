-- ============================================================
-- EaseInn V1 — Migration 00011: Fix Hotel Registration & Properties RLS
-- ============================================================
-- 1. Fix properties SELECT policy so newly registered users can view their created property
-- 2. Stored Procedure: register_hotel_with_manager (SECURITY DEFINER)
-- 3. Grants execute on register_hotel_with_manager
-- ============================================================

-- 1. Fix properties SELECT policy to allow authenticated users to view properties
-- This resolves the Postgres RLS RETURNING error when inserting properties
DROP POLICY IF EXISTS "Users can view assigned property" ON properties;
CREATE POLICY "Users can view assigned property"
  ON properties FOR SELECT
  USING (
    id = current_user_property_id()
    OR auth.uid() IS NOT NULL
  );

-- Ensure properties INSERT policy allows authenticated users
DROP POLICY IF EXISTS "Authenticated users can create a new property" ON properties;
CREATE POLICY "Authenticated users can create a new property"
  ON properties FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- Ensure user_profiles allows users to insert their own profile
DROP POLICY IF EXISTS "Admins can insert or manage profiles for their property" ON user_profiles;
CREATE POLICY "Admins can insert or manage profiles for their property"
  ON user_profiles FOR INSERT
  WITH CHECK (
    id = auth.uid()
    OR (property_id = current_user_property_id() AND current_user_role() = 'admin')
  );

-- 2. Atomic Security Definer Function to create hotel and link manager
CREATE OR REPLACE FUNCTION register_hotel_with_manager(
  p_user_id uuid,
  p_hotel_name text,
  p_city text DEFAULT '',
  p_state text DEFAULT '',
  p_address text DEFAULT '',
  p_phone text DEFAULT '',
  p_email text DEFAULT '',
  p_upi_id text DEFAULT '',
  p_upi_payee_name text DEFAULT '',
  p_full_name text DEFAULT 'General Manager'
)
RETURNS uuid AS $$
DECLARE
  v_property_id uuid;
BEGIN
  -- Insert property first
  INSERT INTO properties (
    name, city, state, address, phone, email, upi_id, upi_payee_name, currency, timezone
  ) VALUES (
    COALESCE(NULLIF(p_hotel_name, ''), 'My Hotel'),
    p_city,
    p_state,
    p_address,
    p_phone,
    p_email,
    p_upi_id,
    p_upi_payee_name,
    'INR',
    'Asia/Kolkata'
  ) RETURNING id INTO v_property_id;

  -- Insert or update user profile with admin role
  INSERT INTO user_profiles (id, property_id, full_name, role, is_active)
  VALUES (p_user_id, v_property_id, COALESCE(NULLIF(p_full_name, ''), 'General Manager'), 'admin', true)
  ON CONFLICT (id) DO UPDATE SET
    property_id = v_property_id,
    full_name = COALESCE(NULLIF(p_full_name, ''), user_profiles.full_name),
    role = 'admin',
    is_active = true,
    updated_at = now();

  RETURN v_property_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execution to authenticated & anon
GRANT EXECUTE ON FUNCTION register_hotel_with_manager TO authenticated, anon;
