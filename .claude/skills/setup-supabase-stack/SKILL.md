---
name: setup-supabase-stack
description: |
  **Supabase stack**: Postgres + Auth + RLS. Adds Supabase CLI as a project
  dev dep, runs `supabase init`, drops the CVC foundation migration
  (`app_role`, `user_roles`, `user_profiles`, `audit_events`, RLS,
  auto-provisioning trigger, redaction-aware audit), seeds two test users,
  and patches the devcontainer to forward Supabase ports + run
  `supabase start` on rebuild.
  Trigger: "add Supabase", "React + Supabase", "FastAPI + Supabase".
---

# Supabase Stack

Wires Supabase into a project that already has the harness + flavor + framework scaffold. Run **last** in compound bootstraps.

## Steps

### 1. Pre-flight

```bash
[ -f CLAUDE.md ] && [ -f scripts/check-patterns.sh ] || {
  echo "Not in a cvc-app-template clone."; exit 1;
}
[ -f package.json ] || [ -f pyproject.toml ] || {
  echo "Run setup-ts-flavor or setup-python-flavor first."; exit 1;
}
[ -f supabase/config.toml ] && {
  echo "Supabase already wired here. Ask user how to proceed."; exit 1;
}
```

**Port collision check** (under DooD, the dev container shares the host's Docker; another running Supabase project will hold the ports):

```bash
running=$(docker ps --filter "name=_supabase_db_" --format '{{.Names}}' 2>/dev/null)
[ -n "$running" ] && {
  echo "Sibling Supabase project running: $running"
  echo "Options: (a) stop it: docker stop \$(docker ps -q --filter 'name=_supabase_')"
  echo "         (b) shift this project's ports in supabase/config.toml + devcontainer.json"
  echo "Ask the user which way to go before proceeding."
  exit 1
}
```

### 2. Install Supabase CLI + init

```bash
npm install -D supabase
printf 'N\nN\n' | npx supabase init --workdir .   # decline IDE auto-prompts
```

Newer CLI may not create `supabase/migrations/` — make sure it exists:

```bash
mkdir -p supabase/migrations
```

### 3. Drop in foundation migration + seed

```bash
ts=$(date -u +%Y%m%d%H%M%S)
cp .claude/skills/setup-supabase-stack/assets/foundation.sql \
   "supabase/migrations/${ts}_foundation.sql"
cp .claude/skills/setup-supabase-stack/assets/seed.sql supabase/seed.sql
```

Foundation creates: `app_role` enum (`admin`/`member`), `user_roles`, `user_profiles`, `audit_events`, `audit_redactions` (opt-in column allowlist for secrets/PII), `has_role()`/`user_has_role()` helpers (SECURITY DEFINER, pinned `search_path`, has_role REVOKEd from PUBLIC), `handle_new_user()` auto-provisioning trigger, `log_audit_event()` with redaction, RLS policies on all four tables.

Seed creates: `admin@localhost.local` / `admin1234` + `member@localhost.local` / `member1234`.

### 4. Patch `.devcontainer/devcontainer.json`

Merge into the JSONC (not jq — file has `//` comments):

- Append `54321, 54322, 54323, 54324` to `forwardPorts`
- Add to `portsAttributes`:
  - `"54321"`: Supabase API (silent)
  - `"54322"`: Supabase Postgres (silent)
  - `"54323"`: Supabase Studio (notify)
  - `"54324"`: Mailpit (silent) — auth-email catcher
- Add `"SUPABASE_ACCESS_TOKEN": "${localEnv:SUPABASE_ACCESS_TOKEN}"` to `remoteEnv`

Validate after editing (python3 is in the container; jq fails on JSONC):

```bash
python3 - <<'PY'
import json, re
src = open('.devcontainer/devcontainer.json').read()
json.loads(re.sub(r'^\s*//.*$', '', src, flags=re.MULTILINE))
print('OK')
PY
```

### 5. Append supabase-start block to `post-create.sh`

Insert between the stack-specific anchor markers, idempotency-gated by sentinel:

```bash
if ! grep -q 'supabase-stack' .devcontainer/post-create.sh; then
  # Insert this block before the "# === END stack-specific hooks ===" line:
  cat <<'BLOCK'
# supabase-stack — start the local stack, write .env.local on rebuild.
if [ -f supabase/config.toml ]; then
  echo -e "${cyan}→ Starting local Supabase (~2-3 min first run)...${reset}"
  npx supabase start
  SB_ENV=$(npx supabase status -o env)
  API_URL=$(printf '%s\n' "$SB_ENV" | awk -F'=' '/^API_URL=/{print $2}' | tr -d '"')
  ANON_KEY=$(printf '%s\n' "$SB_ENV" | awk -F'=' '/^ANON_KEY=/{print $2}' | tr -d '"')
  if [[ -n "$API_URL" && -n "$ANON_KEY" ]]; then
    printf 'VITE_SUPABASE_URL=%s\nVITE_SUPABASE_PUBLISHABLE_KEY=%s\n' "$API_URL" "$ANON_KEY" > .env.local
  fi
fi
BLOCK
fi
```

(For Next.js projects use `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` instead.)

### 6. Append to `.gitignore`

```
# Supabase local state
supabase/.temp/
supabase/.branches/
```

### 7. Add `db:types` script to `package.json`

```json
{ "scripts": { "db:types": "npx supabase gen types typescript --local > src/integrations/supabase/types.ts" } }
```

Run it after rebuild when the local DB is up.

### 8. Hand-off message

> "Supabase wired. Rebuild the dev container (F1 → Dev Containers: Rebuild Container). First rebuild pulls ~10 images. After it's up:
> - http://localhost:54321 — API
> - http://localhost:54323 — Studio
> - http://localhost:54324 — Mailpit (catches auth emails — set `[inbucket].enabled = false` in `supabase/config.toml` to disable)
> - `.env.local` auto-written
>
> Test users: `admin@localhost.local` / `admin1234`, `member@localhost.local` / `member1234`."

## Constraints

- Don't modify the foundation migration after it's been applied anywhere. Add a new migration instead.
- Don't disable RLS on tables you add later. The default-deny stance is non-negotiable.
- Don't INSERT into `audit_events` from app code — only the `log_audit_event()` trigger writes there.
- Don't validate `devcontainer.json` with `jq` — it's JSONC. Use the `python3` snippet in Step 4.
- Don't use the service-role key in client code. Frontend uses anon key only.
