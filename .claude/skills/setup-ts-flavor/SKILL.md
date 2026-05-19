---
name: setup-ts-flavor
description: |
  **TypeScript/JavaScript Flavor**: husky + lint-staged + ESLint complexity
  gates + prettier + gitleaks + osv-scanner. Wires `scripts/check-patterns.sh`
  into `.husky/pre-commit`. Detects Vite+React and uses the React-aware
  ESLint config when present.
  Trigger: "set up TS", "configure JS flavor", or any TS/JS stack request.
---

# TypeScript/JavaScript Flavor

Run **after** the framework scaffold (`setup-vite-react-stack` etc.) so `package.json` reflects the project's real deps. This skill copies canonical configs from `assets/`, installs deps, and patches `.devcontainer/post-create.sh`.

## Steps

### 1. Pre-flight

```bash
[ -f CLAUDE.md ] && [ -f scripts/check-patterns.sh ] || {
  echo "Not in a cvc-app-template clone."; exit 1;
}
[ -f package.json ] || npm init -y
HAS_REACT=0
grep -q '"vite"' package.json 2>/dev/null && grep -q '"react"' package.json 2>/dev/null && HAS_REACT=1
```

### 2. Install dev deps

Pinned: `eslint@^9` (v10 breaks `eslint-plugin-import`), `lint-staged@^16` (v17+ requires Node `22.22+`; devcontainer ships `22.16`).

```bash
npm install -D \
  husky "lint-staged@^16" \
  "eslint@^9" "@eslint/js@^9" \
  typescript-eslint \
  @typescript-eslint/eslint-plugin @typescript-eslint/parser \
  eslint-plugin-sonarjs eslint-plugin-import \
  globals prettier typescript vitest @vitest/coverage-v8
```

`gitleaks` and `osv-scanner` are Go binaries, not on npm. They install inside the dev container via Step 7.

### 3. Copy config assets

```bash
if [ "$HAS_REACT" = "1" ]; then
  cp .claude/skills/setup-ts-flavor/assets/eslint.config.react.js   ./eslint.config.js
else
  cp .claude/skills/setup-ts-flavor/assets/eslint.config.vanilla.js ./eslint.config.js
fi
cp .claude/skills/setup-ts-flavor/assets/.prettierrc      ./.prettierrc
cp .claude/skills/setup-ts-flavor/assets/.osv-scanner.toml ./.osv-scanner.toml
```

(`.prettierrc` is mandatory — without it `prettier --check` defaults to double quotes while the assets use singles; every first commit would fail.)

### 4. Write `tsconfig.json` (only if absent)

If a framework scaffold already wrote one (e.g. Vite did), skip. Otherwise:

```json
{
  "compilerOptions": {
    "target": "ES2022", "module": "ESNext", "moduleResolution": "Bundler",
    "strict": true, "esModuleInterop": true, "skipLibCheck": true,
    "resolveJsonModule": true, "isolatedModules": true, "noEmit": true
  },
  "include": ["src/**/*"]
}
```

### 5. Merge into `package.json`

Add scripts + lint-staged config. **Don't add `toml` to the prettier glob** — Prettier 3.x has no built-in TOML parser, the `.osv-scanner.toml` and `supabase/config.toml` files would block every first commit.

```json
{
  "scripts": {
    "prepare": "husky",
    "lint": "eslint .",
    "type-check": "tsc --noEmit",
    "test": "vitest run --passWithNoTests",
    "test:coverage": "vitest run --coverage --passWithNoTests"
  },
  "lint-staged": {
    "**/*.{ts,tsx,js,jsx,mjs,cjs}": ["npx eslint --max-warnings 0 --no-warn-ignored"],
    "**/*.{json,md,yaml,yml,css,html}": ["npx prettier --check"],
    "**/package-lock.json": ["osv-scanner --lockfile"]
  }
}
```

### 6. Wire husky

```bash
npx husky init
cp .claude/skills/setup-ts-flavor/assets/husky-pre-commit .husky/pre-commit
chmod +x .husky/pre-commit
```

### 7. Patch `.devcontainer/post-create.sh` with the gate-tools installer

Insert the contents of `assets/install-gate-tools.sh` between the `flavor-tooling hooks` anchor markers in `post-create.sh`. Idempotency check first — if a line containing `ts-flavor-tools` is already there, skip.

```bash
if ! grep -q 'ts-flavor-tools' .devcontainer/post-create.sh; then
  awk '
    /# === END flavor-tooling hooks ===/ {
      while ((getline line < ".claude/skills/setup-ts-flavor/assets/install-gate-tools.sh") > 0) print line
      close(".claude/skills/setup-ts-flavor/assets/install-gate-tools.sh")
    }
    { print }
  ' .devcontainer/post-create.sh > /tmp/pc && mv /tmp/pc .devcontainer/post-create.sh
fi
```

### 8. Format the working tree

Run prettier once across the project so existing scaffold files (Vite's `tsconfig.json` ships without trailing newline, etc.) don't trip the lint-staged check on the first commit:

```bash
npx prettier --write \
  'src/**/*.{ts,tsx,css,json}' \
  'index.html' 'package.json' 'tsconfig*.json' \
  'eslint.config.js' 'vite.config.ts' 'README.md' 2>/dev/null || true
```

### 9. Verify (on host)

```bash
npm run lint && npm run build
npx prettier --check '**/*.{ts,tsx,json,md,css}' 'eslint.config.js'
```

All three should pass. **Don't try to commit on the host** — gitleaks + osv-scanner only install inside the dev container (Step 7's block runs on container rebuild).

### 10. Hand-off message

> "TS flavor wired. Lint + build pass. Rebuild the dev container next (F1 → Rebuild) so `gitleaks` + `osv-scanner` install. First commit inside the container will exercise all four pre-commit gates; the patterns gate will refuse until `/check-patterns` stamps."

## Constraints

- Don't soften the complexity gates to make legacy code pass — refactor instead.
- Don't replace `bash scripts/check-patterns.sh` with anything else in the hook.
- Don't add `toml` to the prettier glob (see Step 5).
- Don't combine this skill with stack skills in one pass — run each separately so failures are localized.
