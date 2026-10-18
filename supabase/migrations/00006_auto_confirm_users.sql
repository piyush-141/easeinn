-- ============================================================
-- EaseInn — Auto-Confirm Users & Fix Email Confirmation Issues
-- ============================================================
-- Copy and paste this script into your Supabase Dashboard:
-- SQL Editor -> New Query -> Run
-- This will:
-- 1. Immediately confirm all existing users who are currently unconfirmed
-- 2. Ensure all future user registrations are automatically confirmed on signup

-- Step 1: Immediately confirm all existing unconfirmed users in auth.users
UPDATE auth.users
SET email_confirmed_at = COALESCE(email_confirmed_at, now())
WHERE email_confirmed_at IS NULL;

-- Step 2: Create a function that auto-confirms new users
CREATE OR REPLACE FUNCTION public.handle_auto_confirm_new_user()
RETURNS trigger AS $$
BEGIN
  NEW.email_confirmed_at = COALESCE(NEW.email_confirmed_at, now());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 3: Attach trigger to auth.users table
DROP TRIGGER IF EXISTS trg_auto_confirm_new_user ON auth.users;

CREATE TRIGGER trg_auto_confirm_new_user
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_auto_confirm_new_user();
