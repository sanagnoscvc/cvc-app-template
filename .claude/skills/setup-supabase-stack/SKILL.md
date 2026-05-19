---
name: setup-supabase-stack
description: |
  **Supabase Stack Bootstrap**: Adds Supabase (Postgres + Auth + RLS) to a
  project cloned from `cvc-app-template`. Runs `supabase init`, drops in the
  CVC foundation migration (app_role enum, user_roles, user_profiles,
  audit_events, RLS policies, auto-provisioning trigger), patches the
  devcontainer to forward Supabase ports, patches post-create.sh to run
  `supabase start` and generate .env.local on rebuild.
  Trigger: user asks to "add Supabase", "wire up Supabase", or names a
  Supabase stack (e.g. "React + Supabase", "FastAPI + Supabase").
---

# Supabase Stack Bootstrap

You're adding Supabase (Postgres + Auth + RLS) to a project that was cloned from `cvc-app-template`. This skill encodes the deterministic install + scaffold + devcontainer-patch steps.

After this skill completes:
- `supabase init` has run
- A foundation migration is in place (auth users, role enum, profiles, audit framework, RLS policies, auto-provisioning trigger)
- A seed file with two test users (admin + member) is in place
- The dev container is patched to forward Supabase's ports and start the local stack on rebuild
- The user is prompted to rebuild the container

## Pre-flight

1. Verify you're in a directory cloned from `cvc-app-template`: check that `CLAUDE.md`, `.devcontainer/devcontainer.json`, and `scripts/check-patterns.sh` exist at the repo root. If not, stop and tell the user.
2. Verify a flavor skill has already been applied:
   - For TS projects: `package.json` exists. If not, run `setup-ts-flavor` first.
   - For Python projects: `pyproject.toml` exists. If not, run `setup-python-flavor` first.
3. Verify Supabase isn't already wired: check that `supabase/config.toml` does **not** exist. If it does, the stack is already set up — ask the user what they want done instead (e.g. add a new migration).

## Decisions to make

Ask the user (or infer) if not already clear:

1. **Project ID** — used as the local container prefix (`supabase_db_<project>`). Default: the basename of the workspace folder. Example: if cloned into `my-app/`, project ID = `my-app`. The CLI normalizes this; lowercase + hyphens.
2. **Frontend env-var naming convention** — default `VITE_SUPABASE_URL` / `VITE_SUPABASE_PUBLISHABLE_KEY` (Vite/React). If the project uses Next.js, switch to `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Use what matches the user's frontend.

## Procedure

### Step 1 — Install the Supabase CLI as a project dev dep

TS:
```bash
npm install -D supabase
```

Python: install at the system level (uv tool or pipx), since Python projects don't typically vendor JS-based CLIs:
```bash
uv tool install --python 3.12 supabase || pipx install supabase
```

### Step 2 — Initialize Supabase

```bash
npx supabase init --workdir .
```

Decline VS Code/Cursor IDE auto-prompts (`N` when asked). This creates:
- `supabase/config.toml`
- `supabase/.gitignore`
- empty `supabase/migrations/`

### Step 3 — Drop in the foundation migration

Copy the asset file into the project's migrations dir. Use the current UTC timestamp as the migration prefix (format: `YYYYMMDDHHMMSS`).

```bash
ts=$(date -u +%Y%m%d%H%M%S)
mkdir -p supabase/migrations
cp .claude/skills/setup-supabase-stack/assets/foundation.sql \
   "supabase/migrations/${ts}_foundation.sql"
```

The foundation migration creates:
- `app_role` enum (`admin`, `member`)
- `user_roles`, `user_profiles`, `audit_events` tables
- `has_role()` / `user_has_role()` helpers (SECURITY DEFINER, pinned search_path)
- `update_updated_at_column()` trigger function
- `handle_new_user()` trigger on `auth.users` — auto-provisions role + profile
- `log_audit_event()` trigger function (attach to any business-data table)
- RLS policies: users see own role/profile, admins see all; only SECURITY DEFINER funcs write audit_events

### Step 4 — Drop in the seed

```bash
cp .claude/skills/setup-supabase-stack/assets/seed.sql supabase/seed.sql
```

Creates two test users:

| Email | Password | Role |
|---|---|---|
| `admin@localhost.local` | `admin1234` | admin |
| `member@localhost.local` | `member1234` | member |

**Seed never runs in production** — it only fires on `supabase start`, `supabase db reset`, and preview-branch creation.

### Step 5 — Patch `.devcontainer/devcontainer.json`

Merge the following into the existing JSON (don't overwrite the file). Use a tool (or careful hand-edit) to:

- Append `54321, 54322, 54323` to `forwardPorts` if not present
- Add these entries to `portsAttributes`:
  ```json
  "54321": { "label": "Supabase API",     "onAutoForward": "silent" },
  "54322": { "label": "Supabase Postgres","onAutoForward": "silent" },
  "54323": { "label": "Supabase Studio",  "onAutoForward": "notify" }
  ```
- Add `"SUPABASE_ACCESS_TOKEN": "${localEnv:SUPABASE_ACCESS_TOKEN}"` to `remoteEnv`

Re-read the file after editing and check JSON is still valid (use `jq . .devcontainer/devcontainer.json`).

### Step 6 — Patch `.devcontainer/post-create.sh`

Append the supabase-start block **between** the anchor markers:

```bash
# === BEGIN stack-specific hooks (appended by setup-*-stack skills) ===
# ↑ append above this line
# === END stack-specific hooks ===
```

The block to append (uses awk to parse status output, robust to CLI flag changes):

```bash
if [ -f supabase/config.toml ]; then
  echo -e "${cyan}→ Starting local Supabase (first run pulls ~10 images, ~2-3 min)...${reset}"
  npx supabase start

  echo -e "${cyan}→ Writing .env.local from supabase status...${reset}"
  SB_ENV=$(npx supabase status -o env)
  API_URL=$(printf '%s\n' "$SB_ENV" | awk -F'=' '/^API_URL=/{print $2}' | tr -d '"')
  ANON_KEY=$(printf '%s\n' "$SB_ENV" | awk -F'=' '/^ANON_KEY=/{print $2}' | tr -d '"')
  if [[ -z "$API_URL" || -z "$ANON_KEY" ]]; then
    echo "  WARN: couldn't parse API_URL/ANON_KEY from supabase status -o env" >&2
    printf '%s\n' "$SB_ENV" >&2
  else
    cat > .env.local <<EOF
VITE_SUPABASE_URL=$API_URL
VITE_SUPABASE_PUBLISHABLE_KEY=$ANON_KEY
EOF
    echo -e "  ${green}.env.local written.${reset}"
  fi
fi
```

If the project is Next.js (decision in pre-flight), use `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` in the .env.local block instead.

Use `sed` or careful insertion to place this block before the `# === END stack-specific hooks ===` line. Verify the file still has both anchor markers afterward.

### Step 7 — Add Supabase entries to `.gitignore`

If not already present, append:

```
# Supabase local state
supabase/.temp/
supabase/.branches/
```

(The baseline `.gitignore` should already include `.env.local`.)

### Step 8 — Generate the typed Supabase types (TS only)

Add this script to `package.json`:

```json
"scripts": {
  "db:types": "npx supabase gen types typescript --local > src/integrations/supabase/types.ts"
}
```

(Run it after Supabase has actually started in step 9; not before, since it queries the local DB.)

### Step 9 — Prompt the user to rebuild the container

Tell the user:

> "Supabase wired into the project. The devcontainer now forwards Supabase's ports and `post-create.sh` will `supabase start` on every container rebuild.
>
> **Rebuild the container** now (`F1` → *Dev Containers: Rebuild Container*) so the changes take effect. First rebuild will pull ~10 Docker images (~2-3 min).
>
> After the rebuild completes, you'll have:
> - http://localhost:54321 — Supabase API
> - http://localhost:54322 — Postgres
> - http://localhost:54323 — Supabase Studio (DB browser)
> - `.env.local` auto-generated with the API URL + anon key
>
> Test users:
> - `admin@localhost.local` / `admin1234` (admin)
> - `member@localhost.local` / `member1234` (member)"

## What you've added

```
supabase/
├── config.toml                              (from supabase init)
├── .gitignore                               (from supabase init)
├── seed.sql                                 (from this skill)
└── migrations/
    └── <timestamp>_foundation.sql           (from this skill)

package.json                                 (← scripts.db:types added; supabase devDep added)
.gitignore                                   (← supabase/.temp + supabase/.branches added)
.devcontainer/devcontainer.json              (← Supabase ports + SUPABASE_ACCESS_TOKEN added)
.devcontainer/post-create.sh                 (← supabase start block appended between anchors)
```

## What NOT to do

- **Don't modify the foundation migration after applying** to a project that's been shared. Migrations are immutable once any teammate has applied them; add a new migration instead.
- **Don't disable RLS** on any new tables you add later. The foundation's default-deny stance is non-negotiable.
- **Don't INSERT into `audit_events`** from app code. The table has no INSERT policy by design — only the `log_audit_event()` trigger function (SECURITY DEFINER) is allowed to write.
- **Don't put the Supabase start logic outside the anchor markers** in post-create.sh. Other stack skills append between the same markers; respecting the contract keeps them composable.
- **Don't use the service-role key in client code**. The frontend only ever uses the anon key (`VITE_SUPABASE_PUBLISHABLE_KEY`); the service-role key is for server-only contexts.
