-- ============================================================
-- EaseInn V1 — Hotel Primary, Manager Secondary Architecture
-- ============================================================
-- Enforces:
-- 1. Property (Hotel) is the primary root entity.
-- 2. Manager accounts (user_profiles) are secondary entities attached to a property.
-- 3. One hotel can have multiple managers / staff members.
-- 4. No seed data is included.
-- ============================================================

-- 1. Ensure foreign key on user_profiles correctly references properties
-- (Properties must exist before user_profiles can reference it)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'user_profiles_property_id_fkey'
      AND table_name = 'user_profiles'
  ) THEN
    ALTER TABLE user_profiles
      ADD CONSTRAINT user_profiles_property_id_fkey
      FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE SET NULL;
  END IF;
END $$;

-- 2. Explicit index for multiple managers per property lookup
CREATE INDEX IF NOT EXISTS idx_user_profiles_property_id
  ON user_profiles(property_id);

-- 3. Stored Procedure: Register Primary Property First
-- Returns the new property UUID so manager(s) can be attached immediately.
CREATE OR REPLACE FUNCTION register_property_primary(
  p_name text,
  p_city text,
  p_state text DEFAULT '',
  p_address text DEFAULT '',
  p_phone text DEFAULT '',
  p_email text DEFAULT '',
  p_upi_id text DEFAULT '',
  p_upi_payee_name text DEFAULT '',
  p_total_rooms integer DEFAULT 12
)
RETURNS uuid AS $$
DECLARE
  v_property_id uuid;
BEGIN
  INSERT INTO properties (
    name,
    city,
    state,
    address,
    phone,
    email,
    upi_id,
    upi_payee_name,
    currency,
    timezone
  ) VALUES (
    p_name,
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

  RETURN v_property_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Stored Procedure: Assign Manager to Property (Supports Multiple Managers)
CREATE OR REPLACE FUNCTION assign_manager_to_property(
  p_user_id uuid,
  p_property_id uuid,
  p_full_name text,
  p_role text DEFAULT 'admin'
)
RETURNS void AS $$
BEGIN
  -- Verify the property exists before attaching manager
  IF NOT EXISTS (SELECT 1 FROM properties WHERE id = p_property_id) THEN
    RAISE EXCEPTION 'Property % does not exist.', p_property_id;
  END IF;

  INSERT INTO user_profiles (id, property_id, full_name, role, is_active)
  VALUES (p_user_id, p_property_id, p_full_name, p_role, true)
  ON CONFLICT (id) DO UPDATE SET
    property_id = EXCLUDED.property_id,
    full_name = EXCLUDED.full_name,
    role = EXCLUDED.role,
    is_active = true,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Stored Procedure: Get All Managers for a Property
CREATE OR REPLACE FUNCTION get_property_managers(p_property_id uuid)
RETURNS TABLE (
  manager_id uuid,
  full_name text,
  role text,
  is_active boolean,
  created_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    u.id AS manager_id,
    u.full_name,
    u.role,
    u.is_active,
    u.created_at
  FROM user_profiles u
  WHERE u.property_id = p_property_id
  ORDER BY u.created_at ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
