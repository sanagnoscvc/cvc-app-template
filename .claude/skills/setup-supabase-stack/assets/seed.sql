-- Seed data for local Supabase development. Runs after migrations on
-- `supabase start`, `supabase db reset`, and preview-branch creation.
-- Does NOT run in production (production state comes from migrations, not seed).

-- ---------------------------------------------------------------------------
-- Test users
-- ---------------------------------------------------------------------------
-- Deterministic UUIDs make refs stable across reseeds.
-- handle_new_user() trigger auto-provisions user_roles + user_profiles entries.

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change
)
VALUES
  (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000001',
    'authenticated', 'authenticated',
    'admin@localhost.local',
    crypt('admin1234', gen_salt('bf')),
    now(),
    '{"provider": "email", "providers": ["email"]}',
    '{"display_name": "Admin User"}',
    now(), now(), '', '', '', ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000002',
    'authenticated', 'authenticated',
    'member@localhost.local',
    crypt('member1234', gen_salt('bf')),
    now(),
    '{"provider": "email", "providers": ["email"]}',
    '{"display_name": "Member User"}',
    now(), now(), '', '', '', ''
  )
ON CONFLICT (id) DO NOTHING;

-- Promote the admin user (the member trigger already gave them 'member')
UPDATE public.user_roles
   SET role = 'admin'
 WHERE user_id = '00000000-0000-0000-0000-000000000001';
