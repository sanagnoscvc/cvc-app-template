---
name: setup-vite-react-stack
description: |
  **Vite + React (+ optional Supabase auth glue) Stack Bootstrap**: scaffolds a
  Vite + React + TypeScript SPA in a clone of `cvc-app-template`. Sets up the
  CVC conventions: port 8080, `@` path alias, `@vitejs/plugin-react-swc`,
  Tailwind v4 via `@tailwindcss/vite`, react-router-dom, and (if Supabase is
  in scope) the standard `src/integrations/supabase/client.ts` + Login /
  ProtectedRoute / Dashboard skeleton.
  Trigger: user asks for a "React + Vite app", "Vite + Supabase", "minimal
  SPA", or any web frontend in TypeScript on this template.
---

# Vite + React Stack Bootstrap

You're scaffolding a Vite + React + TypeScript SPA into a clone of `cvc-app-template`. This skill encodes all the deterministic Vite/React decisions — port, alias, plugin choice, Tailwind setup, app skeleton — so you don't have to re-derive them per project.

After this skill completes:
- A working Vite/React + TypeScript project is in place
- Port 8080, `@` alias, SWC React plugin, Tailwind v4 wired
- `react-router-dom` installed with routes for `/login` and `/` (protected)
- If `setup-supabase-stack` has been run (or will be), the auth glue (`client.ts`, `ProtectedRoute`, `LoginPage`, `Dashboard`) is in place
- All scaffold cruft removed (no `App.css`, no `assets/react.svg`, no demo counter)

## Pre-flight

1. Verify you're in a clone of `cvc-app-template`: `CLAUDE.md`, `.devcontainer/devcontainer.json`, `scripts/check-patterns.sh` exist at repo root.
2. **Detect Vite presence using Vite-specific markers** (not just `package.json` existence — `setup-ts-flavor` creates an empty `package.json` via `npm init -y` and we don't want to mistake that for "Vite already scaffolded"):

   ```bash
   has_vite=0
   if [ -f vite.config.ts ] || [ -f vite.config.js ]; then has_vite=1; fi
   if [ -f package.json ] && grep -q '"vite"' package.json; then has_vite=1; fi
   if [ -f index.html ] && [ -f src/main.tsx ]; then has_vite=1; fi
   ```

   - **`has_vite=1`** → skip Step 1 (scaffold). Go straight to Step 2 (customize).
   - **`has_vite=0`** → run Step 1, even if `package.json` exists (e.g. from `setup-ts-flavor`'s `npm init -y`). Step 1 handles the bare-package.json merge case.

3. **Recommended skill order** (tell the user if there's ambiguity): run **this skill first**, then `setup-ts-flavor`, then `setup-supabase-stack`. Reverse orders work but each combination has caveats — see Step 1's note on merging.

4. Tell the user: *"This skill scaffolds Vite + React + TS, installs Tailwind v4, and wires the standard app skeleton. If you also want Supabase auth, run `setup-supabase-stack` after. If you want the lint/format/test harness, run `setup-ts-flavor` after."*

## Decisions to make

Ask the user (or infer) if unclear:

1. **Supabase auth glue?** — default **yes** for "React + Supabase" prompts. Writes `src/integrations/supabase/client.ts`, `ProtectedRoute`, `LoginPage`, `Dashboard`. If the user wants a different backend (FastAPI, etc.), say no and write only `App.tsx` placeholder.

Don't ask about port, alias, plugin, or Tailwind — those are CVC conventions baked in.

## Procedure

### Step 1 — Scaffold Vite via `/tmp` (non-destructive)

**Do not** run `npm create vite@latest .` in the harness root with `--overwrite` — it wipes `CLAUDE.md`, `.claude/`, `.devcontainer/`, `.github/`, `scripts/`, `README.md`. Scaffold to `/tmp` and copy the framework files in.

```bash
rm -rf /tmp/vite-scaffold
mkdir /tmp/vite-scaffold
cd /tmp/vite-scaffold
npm create vite@latest app -- --template react-ts
cd -   # back to the project root
```

**Note**: `react-swc-ts` was removed in `create-vite` v9. Only `react-ts` remains. We swap the plugin manually in Step 3.

**Handle the existing-package.json case before copying.** If `setup-ts-flavor` ran first, there's already a `package.json` (from `npm init -y`) that may have a custom `"name"` set. Don't blindly overwrite — capture it first:

```bash
existing_pkg=""
if [ -f package.json ]; then
  existing_pkg=$(cat package.json)
fi
```

Copy framework files. If `existing_pkg` was non-empty AND non-bare (has scripts/deps beyond `npm init -y` defaults), refuse and ask the user to either remove `package.json` first or run `setup-vite-react-stack` *before* the other skill. Otherwise overwrite — `npm init -y`'s output has no value to preserve:

```bash
cp -r /tmp/vite-scaffold/app/. ./
# Restore harness files Vite's template also ships
git checkout -- .gitignore README.md 2>/dev/null || true
rm -rf /tmp/vite-scaffold
```

If `existing_pkg` was substantial (e.g. lint-staged config from `setup-ts-flavor`), then *merge* its `"scripts"`, `"dependencies"`, `"devDependencies"`, and `"lint-staged"` keys into the new Vite `package.json` using `jq`:

```bash
echo "$existing_pkg" > /tmp/old-pkg.json
jq -s '
  .[1] as $vite | .[0] as $old |
  $vite * { scripts: ($vite.scripts + ($old.scripts // {})),
            dependencies: ($vite.dependencies + ($old.dependencies // {})),
            devDependencies: ($vite.devDependencies + ($old.devDependencies // {})),
            "lint-staged": ($old["lint-staged"] // null) }
' /tmp/old-pkg.json package.json > package.json.merged
mv package.json.merged package.json
rm /tmp/old-pkg.json
```

After this, the project has both the harness AND a Vite scaffold. `git status` should show ~6-8 new untracked files (`index.html`, `package.json`, `tsconfig*.json`, `vite.config.ts`, `src/`, `public/`, `eslint.config.js`).

### Step 2 — Pin ESLint to ^9 in `package.json`

Vite scaffolds with `eslint@^10` and `@eslint/js@^10`. The TS flavor's `eslint-plugin-import` requires ESLint 9. Update `package.json`:

```json
{
  "devDependencies": {
    "eslint": "^9.36.0",
    "@eslint/js": "^9.36.0"
  }
}
```

If `setup-ts-flavor` will run later it does this itself; doing it here also avoids a temporary inconsistency if the user runs `npm install` between skills.

### Step 3 — Swap React plugin to SWC

```bash
npm uninstall @vitejs/plugin-react
npm install -D @vitejs/plugin-react-swc
```

### Step 4 — Install Tailwind v4

```bash
npm install -D tailwindcss @tailwindcss/vite
```

No `tailwind.config.js` or `postcss.config.js` needed — v4 is config-via-CSS.

### Step 5 — Install runtime deps

```bash
npm install @supabase/supabase-js react-router-dom
```

(Install `@supabase/supabase-js` regardless of whether the Supabase stack will be wired — the client file imports it. If the user explicitly opts out of Supabase glue in pre-flight, skip both installs and skip Step 8.)

### Step 6 — Replace `vite.config.ts`

Overwrite with the canonical CVC config:

```bash
cp .claude/skills/setup-vite-react-stack/assets/vite.config.ts ./vite.config.ts
```

That sets port 8080, `host: true`, `strictPort: true`, `@` alias to `./src`, and the react-swc + tailwindcss plugins.

### Step 7 — Patch `tsconfig.app.json` to add the `@` path alias

Read the existing `tsconfig.app.json` (Vite scaffolded it) and merge in:

```json
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./src/*"]
    }
  }
}
```

**Don't** add `"baseUrl": "."` — it's deprecated in TS 6 and the path is resolved relative to the tsconfig file by default.

### Step 8 — Wipe the demo scaffold and write the app skeleton

Remove Vite's demo files:

```bash
rm -f src/App.css src/App.tsx src/counter.ts src/style.css
rm -rf src/assets public/vite.svg
```

Make the app dirs and copy the canonical skeleton:

```bash
mkdir -p src/components src/pages src/integrations/supabase
cp .claude/skills/setup-vite-react-stack/assets/main.tsx                 src/main.tsx
cp .claude/skills/setup-vite-react-stack/assets/index.css                src/index.css
cp .claude/skills/setup-vite-react-stack/assets/client.ts                src/integrations/supabase/client.ts
cp .claude/skills/setup-vite-react-stack/assets/ProtectedRoute.tsx       src/components/ProtectedRoute.tsx
cp .claude/skills/setup-vite-react-stack/assets/LoginPage.tsx            src/pages/LoginPage.tsx
cp .claude/skills/setup-vite-react-stack/assets/Dashboard.tsx            src/pages/Dashboard.tsx
```

If the user opted out of Supabase glue in pre-flight, skip the `client.ts`, `ProtectedRoute.tsx`, `LoginPage.tsx`, `Dashboard.tsx` copies and instead write a minimal `App.tsx` placeholder that gets rendered directly (you'll also need to edit `main.tsx` accordingly).

### Step 9 — Update `index.html` title

Change the `<title>` to the project name (the workspace folder basename):

```html
<title>my-app</title>
```

Drop the favicon link if there's no `public/favicon.svg` (you deleted `public/vite.svg`).

### Step 10 — Add app `name` + scripts to `package.json`

Set `"name"` to the workspace folder basename if Vite scaffolded it as `"app"`.

`setup-ts-flavor` will add the lint/test scripts later (or has already). If neither setup-ts-flavor nor any other skill has touched scripts, ensure at minimum the Vite defaults are present (`dev`, `build`, `preview`).

### Step 11 — Verify

Run the trifecta:

```bash
npm install                      # if you haven't already
npx tsc --noEmit -p tsconfig.app.json   # or `npm run type-check` if scripted
npm run build
```

All three should pass. If `npm install` errors with `ERESOLVE` mentioning `eslint`, you forgot Step 2 — pin to `^9` and retry.

### Step 12 — Tell the user what's next

> "Vite + React scaffold complete. Pre-rebuild sanity checks all passed (type-check, build).
>
> Outstanding (in order):
> - If `setup-ts-flavor` hasn't run yet, run it now to add husky + lint-staged + complexity gates + the pattern-check gate.
> - If `setup-supabase-stack` hasn't run yet, run it now so the auth glue has a backend to talk to. Without it, the app boots but `.env.local` is missing and login fails with a 'Missing Supabase env vars' error.
> - Then rebuild the dev container so the supabase stack's post-create patches kick in (`supabase start` + `.env.local` generation)."

## What you've added

```
package.json                           ← Vite/React deps, ESLint pinned ^9
package-lock.json                      ← (auto)
tsconfig.json, tsconfig.app.json,
tsconfig.node.json                     ← TS configs (path alias added)
vite.config.ts                         ← CVC convention: 8080 + @ alias + SWC + Tailwind
index.html                             ← title set
src/main.tsx                           ← BrowserRouter + routes
src/index.css                          ← @import 'tailwindcss';
src/integrations/supabase/client.ts    ← (if Supabase) the supabase client
src/components/ProtectedRoute.tsx      ← (if Supabase) auth guard
src/pages/LoginPage.tsx                ← (if Supabase) email + password form
src/pages/Dashboard.tsx                ← (if Supabase) welcome + logout
```

## What NOT to do

- **Don't run `npm create vite@latest .` in the project root**. Use `/tmp` + copy. `--overwrite` flag is destructive in a harness clone.
- **Don't use the `react-swc-ts` template** — removed in `create-vite` v9. Use `react-ts` and swap the plugin in Step 3.
- **Don't keep `@vitejs/plugin-react`** — CVC convention is SWC for faster builds.
- **Don't add `baseUrl` to tsconfig** — deprecated in TS 6, the path is now resolved relative to the tsconfig file.
- **Don't write the Supabase auth glue if the user explicitly opted out** — write a placeholder `App.tsx` instead so the build still passes.
- **Don't combine with `setup-supabase-stack` or `setup-ts-flavor` in one go**. Each is independent; the user runs them in whichever order makes sense.
