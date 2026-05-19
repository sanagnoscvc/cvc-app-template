---
name: setup-vite-react-stack
description: |
  **Vite + React + TS stack**: scaffolds the SPA. Port 8080, `@` path alias,
  `@vitejs/plugin-react-swc`, Tailwind v4 (via `@tailwindcss/vite`),
  `react-router-dom`, and the standard Supabase auth glue
  (`client.ts` + `ProtectedRoute` + `LoginPage` + `Dashboard`).
  Trigger: "React + Vite app", "Vite + Supabase", "minimal SPA".
---

# Vite + React Stack

Scaffolds Vite + React + TypeScript in a cloned `cvc-app-template`. Canonical configs live in `assets/`; this skill mostly `cp`s them.

**Order**: run this FIRST in compound bootstraps, before `setup-ts-flavor` and `setup-supabase-stack`. Flavor and Supabase skills detect this scaffold and compose with it.

## Steps

### 1. Pre-flight

```bash
[ -f CLAUDE.md ] || { echo "Not in a cvc-app-template clone."; exit 1; }
HAS_VITE=0
[ -f vite.config.ts ] || [ -f vite.config.js ] && HAS_VITE=1
grep -q '"vite"' package.json 2>/dev/null && HAS_VITE=1
[ -f index.html ] && [ -f src/main.tsx ] && HAS_VITE=1
```

If `HAS_VITE=1`: skip Step 2 (scaffold). Otherwise proceed.

### 2. Scaffold via `/tmp` (non-destructive)

**Don't** run `npm create vite@latest .` in the harness — `--overwrite` wipes `CLAUDE.md`, `.claude/`, `.devcontainer/`, etc.

```bash
rm -rf /tmp/vite-scaffold && mkdir /tmp/vite-scaffold
(cd /tmp/vite-scaffold && npm create vite@latest app -- --template react-ts)

# Preserve any existing package.json content
existing_pkg=""
[ -f package.json ] && existing_pkg=$(cat package.json)

cp -r /tmp/vite-scaffold/app/. ./
git checkout -- .gitignore README.md 2>/dev/null || true
rm -rf /tmp/vite-scaffold

# Merge existing package.json (if not bare from `npm init -y`)
if [ -n "$existing_pkg" ] && echo "$existing_pkg" | grep -q '"scripts"' && echo "$existing_pkg" | grep -q '"lint-staged"\|"husky"'; then
  echo "$existing_pkg" > /tmp/old-pkg.json
  jq -s '
    .[1] as $vite | .[0] as $old |
    $vite * { scripts: ($vite.scripts + ($old.scripts // {})),
              dependencies: ($vite.dependencies + ($old.dependencies // {})),
              devDependencies: ($vite.devDependencies + ($old.devDependencies // {})),
              "lint-staged": ($old["lint-staged"] // null) }
  ' /tmp/old-pkg.json package.json > /tmp/merged && mv /tmp/merged package.json
  rm /tmp/old-pkg.json
fi
```

**Note**: `react-swc-ts` was removed in `create-vite` v9. We scaffold `react-ts` and swap the plugin in Step 3.

### 3. Swap plugin + install deps

```bash
npm uninstall @vitejs/plugin-react
npm install -D @vitejs/plugin-react-swc tailwindcss @tailwindcss/vite
npm install @supabase/supabase-js react-router-dom
```

Pin `eslint@^9` if Vite scaffolded ESLint at v10 (causes `ERESOLVE` later with `eslint-plugin-import`):

```bash
if grep -q '"eslint": "\^10' package.json; then
  npm install -D "eslint@^9" "@eslint/js@^9"
fi
```

### 4. Copy canonical configs + app skeleton

```bash
cp .claude/skills/setup-vite-react-stack/assets/vite.config.ts ./vite.config.ts
```

Add the `@` path alias to `tsconfig.app.json` by merging in:

```json
{ "compilerOptions": { "paths": { "@/*": ["./src/*"] } } }
```

(Don't add `baseUrl` — deprecated in TS 6.)

### 5. Wipe Vite demo files; write app skeleton

`create-vite@9` ships `src/App.tsx`, `src/index.css`, `src/assets/react.svg`, `public/icons.svg`, `public/favicon.svg`. Keep `favicon.svg` (referenced by `index.html`); remove the rest:

```bash
rm -f src/App.css src/App.tsx src/style.css src/counter.ts
rm -rf src/assets
rm -f public/icons.svg public/vite.svg   # vite.svg only in older scaffolds — rm -f safe either way

mkdir -p src/components src/pages src/integrations/supabase

cp .claude/skills/setup-vite-react-stack/assets/main.tsx           src/main.tsx
cp .claude/skills/setup-vite-react-stack/assets/index.css          src/index.css
cp .claude/skills/setup-vite-react-stack/assets/client.ts          src/integrations/supabase/client.ts
cp .claude/skills/setup-vite-react-stack/assets/ProtectedRoute.tsx src/components/ProtectedRoute.tsx
cp .claude/skills/setup-vite-react-stack/assets/LoginPage.tsx      src/pages/LoginPage.tsx
cp .claude/skills/setup-vite-react-stack/assets/Dashboard.tsx      src/pages/Dashboard.tsx
```

If the user opted out of Supabase glue in pre-flight conversation, skip the four Supabase-auth files and write a placeholder `App.tsx` instead.

### 6. Update `index.html` title

Change `<title>app</title>` to the workspace folder basename. Don't touch the favicon link — `public/favicon.svg` exists.

### 7. Verify

```bash
npm install
npx tsc --noEmit -p tsconfig.app.json
npm run build
```

All three must pass. Strip the build artifacts: `rm -rf dist`.

### 8. Hand-off message

> "Vite + React scaffolded. Type-check + build pass. Next: run `setup-ts-flavor` (adds the pre-commit pipeline) and `setup-supabase-stack` (wires Supabase auth). Then rebuild the dev container."

## Constraints

- Don't use `npm create vite@latest .` directly — scaffold to `/tmp` and copy.
- Don't use the `react-swc-ts` template (removed in `create-vite` v9). Use `react-ts` and swap the plugin manually.
- Don't add `baseUrl` to tsconfig.
- Don't bundle this skill's work with `setup-ts-flavor` or `setup-supabase-stack` in one pass.
