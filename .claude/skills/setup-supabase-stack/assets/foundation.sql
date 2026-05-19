-- =============================================================================
-- Foundation migration: base infrastructure for any Supabase-backed CVC app.
-- Creates: app_role enum, user_roles, user_profiles, audit_events, plus the
-- core RLS policies and the auto-provisioning trigger so a new auth user
-- automatically gets a profile + member role.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Custom enum: app_role
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_role') THEN
    CREATE TYPE public.app_role AS ENUM ('admin', 'member');
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- 2. Trigger function: auto-update updated_at columns
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Table: user_roles
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_roles (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role       app_role    NOT NULL DEFAULT 'member',
  created_at timestamptz DEFAULT now(),
  CONSTRAINT uq_user_roles_user_id UNIQUE (user_id)
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 4. Role-check helpers (SECURITY DEFINER with pinned search_path)
--
-- Two functions, two intended audiences:
--   * public.has_role(uid, r) — INTERNAL only. Used by RLS policies and
--     SECURITY DEFINER triggers. EXECUTE is REVOKED from PUBLIC below so
--     authenticated users cannot probe arbitrary users' roles directly.
--   * public.user_has_role(r) — exposed to `authenticated`. Always uses
--     auth.uid(), so a caller can only check their own roles. This is the
--     function RLS policies should use externally.
--
-- RLS policies below call user_has_role(text) (no arbitrary uid).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_role(uid uuid, r app_role)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Admins implicitly hold every role.
  IF EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = uid AND role = 'admin'
  ) THEN
    RETURN true;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = uid AND role = r
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.user_has_role(r text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.has_role(auth.uid(), r::app_role);
END;
$$;

-- Lock down has_role(uid, role): no PUBLIC execute. RLS policies call
-- it via SECURITY DEFINER through user_has_role, which is the only
-- exposed entry point for authenticated clients.
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.user_has_role(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.user_has_role(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Table: user_profiles
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_profiles (
  id           uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text        NOT NULL DEFAULT '',
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trg_user_profiles_updated_at ON public.user_profiles;
CREATE TRIGGER trg_user_profiles_updated_at
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ---------------------------------------------------------------------------
-- 6. Trigger: auto-provision role + profile for new auth users
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, 'member')
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_profiles (id, display_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'display_name', '')
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 7a. Table: audit_redactions
--
-- The audit framework (below) records before/after row snapshots as JSONB.
-- Some columns will inevitably hold secrets or PII (password reset tokens,
-- SSNs, internal IDs). This table lets you declare which columns to strip
-- from the snapshot BEFORE it lands in audit_events.
--
-- Empty by default: out of the box, every column is logged. Add a row per
-- (table, column) you want redacted. Apply in a migration, not at runtime.
--
-- Example:
--   INSERT INTO public.audit_redactions(table_name, column_name, reason)
--   VALUES ('user_profiles', 'phone_number', 'PII — not needed in audit');
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_redactions (
  table_name  text NOT NULL,
  column_name text NOT NULL,
  reason      text,
  created_at  timestamptz DEFAULT now(),
  CONSTRAINT pk_audit_redactions PRIMARY KEY (table_name, column_name)
);

ALTER TABLE public.audit_redactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can read audit redactions" ON public.audit_redactions;
CREATE POLICY "Admins can read audit redactions"
  ON public.audit_redactions FOR SELECT
  USING (public.user_has_role('admin'));

-- Helper: strip configured columns from a JSONB row snapshot. Used by
-- log_audit_event() below. SECURITY DEFINER + pinned search_path so it
-- reads audit_redactions regardless of caller permissions.
CREATE OR REPLACE FUNCTION public.audit_redact(payload jsonb, p_table_name text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_col text;
BEGIN
  IF payload IS NULL THEN
    RETURN NULL;
  END IF;
  FOR v_col IN
    SELECT column_name FROM public.audit_redactions WHERE table_name = p_table_name
  LOOP
    payload := payload - v_col;
  END LOOP;
  RETURN payload;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.audit_redact(jsonb, text) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- 7b. Table: audit_events + generic log_audit_event() trigger function
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_events (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type  text        NOT NULL,
  target_id    uuid        NOT NULL,
  action       text        NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
  actor_id     uuid,
  actor_email  text,
  before_state jsonb,
  after_state  jsonb,
  diff         jsonb,
  ip_address   text,
  user_agent   text,
  created_at   timestamptz DEFAULT now()
);

ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_audit_events__target_type_target_id
  ON public.audit_events (target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_events__actor_id
  ON public.audit_events (actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_events__created_at
  ON public.audit_events (created_at);

-- Generic audit-logging trigger function — attach to any table whose
-- INSERT/UPDATE/DELETE you want recorded. Never INSERT into audit_events
-- directly from app code (there's no INSERT policy by design — only
-- SECURITY DEFINER functions like this one can write).
CREATE OR REPLACE FUNCTION public.log_audit_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_action   text;
  v_old      jsonb;
  v_new      jsonb;
  v_diff     jsonb;
  v_target   uuid;
BEGIN
  v_action := TG_OP;

  IF TG_OP = 'DELETE' THEN
    v_old    := public.audit_redact(to_jsonb(OLD), TG_TABLE_NAME);
    v_new    := NULL;
    v_target := OLD.id;
  ELSIF TG_OP = 'INSERT' THEN
    v_old    := NULL;
    v_new    := public.audit_redact(to_jsonb(NEW), TG_TABLE_NAME);
    v_target := NEW.id;
  ELSE
    v_old    := public.audit_redact(to_jsonb(OLD), TG_TABLE_NAME);
    v_new    := public.audit_redact(to_jsonb(NEW), TG_TABLE_NAME);
    v_target := NEW.id;
    SELECT jsonb_object_agg(key, jsonb_build_object('old', v_old -> key, 'new', value))
    INTO v_diff
    FROM jsonb_each(v_new)
    WHERE v_old -> key IS DISTINCT FROM value;
  END IF;

  INSERT INTO public.audit_events (
    target_type, target_id, action,
    actor_id, actor_email,
    before_state, after_state, diff
  ) VALUES (
    TG_TABLE_NAME, v_target, v_action,
    auth.uid(),
    COALESCE(current_setting('request.jwt.claims', true)::jsonb ->> 'email', NULL),
    v_old, v_new, v_diff
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. RLS policies
-- ---------------------------------------------------------------------------

-- ---- user_roles ----
DROP POLICY IF EXISTS "Users can read own role" ON public.user_roles;
CREATE POLICY "Users can read own role"
  ON public.user_roles FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins can read all roles" ON public.user_roles;
CREATE POLICY "Admins can read all roles"
  ON public.user_roles FOR SELECT
  USING (public.user_has_role('admin'));

DROP POLICY IF EXISTS "Admins can insert roles" ON public.user_roles;
CREATE POLICY "Admins can insert roles"
  ON public.user_roles FOR INSERT
  WITH CHECK (public.user_has_role('admin'));

DROP POLICY IF EXISTS "Admins can update roles" ON public.user_roles;
CREATE POLICY "Admins can update roles"
  ON public.user_roles FOR UPDATE
  USING (public.user_has_role('admin'))
  WITH CHECK (public.user_has_role('admin'));

DROP POLICY IF EXISTS "Admins can delete roles" ON public.user_roles;
CREATE POLICY "Admins can delete roles"
  ON public.user_roles FOR DELETE
  USING (public.user_has_role('admin'));

-- ---- user_profiles ----
DROP POLICY IF EXISTS "Users can read own profile" ON public.user_profiles;
CREATE POLICY "Users can read own profile"
  ON public.user_profiles FOR SELECT
  USING (id = auth.uid());

DROP POLICY IF EXISTS "Admins can read all profiles" ON public.user_profiles;
CREATE POLICY "Admins can read all profiles"
  ON public.user_profiles FOR SELECT
  USING (public.user_has_role('admin'));

DROP POLICY IF EXISTS "Users can update own profile" ON public.user_profiles;
CREATE POLICY "Users can update own profile"
  ON public.user_profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "Admins can update any profile" ON public.user_profiles;
CREATE POLICY "Admins can update any profile"
  ON public.user_profiles FOR UPDATE
  USING (public.user_has_role('admin'))
  WITH CHECK (public.user_has_role('admin'));

-- ---- audit_events ----
DROP POLICY IF EXISTS "Admins can read audit events" ON public.audit_events;
CREATE POLICY "Admins can read audit events"
  ON public.audit_events FOR SELECT
  USING (public.user_has_role('admin'));

-- =============================================================================
-- End of foundation migration
-- =============================================================================
