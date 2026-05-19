---
name: setup-ts-flavor
description: |
  **TypeScript/JavaScript Flavor Bootstrap**: Wires the CLAUDE.md hooks contract
  into a TS/JS project using husky + lint-staged (npm-native idiom). Installs
  ESLint complexity gates, secretlint, osv-scanner, prettier, vitest. Wires the
  check-patterns gate into the husky pre-commit hook.
  Trigger: user asks to "set up TS", "bootstrap TypeScript", "configure JS
  flavor", or names a TS/JS stack in a fresh clone (e.g. "set me up for
  TS + Supabase", "Vite + React project").
---

# TypeScript / JavaScript Flavor Bootstrap

You're configuring a clone of `cvc-app-template` for a TS or JS project. This skill encodes the **deterministic** parts: install the right tooling, write the canonical configs, wire `scripts/check-patterns.sh` into the husky pre-commit hook.

After this skill completes, the project will satisfy all five gates in the CLAUDE.md hooks contract (secrets, dep vulns, hygiene, patterns, lint+complexity).

## Decisions to make before starting

Ask the user (or infer from their stack request) if not already clear:

1. **Runtime environment**: `browser`, `node`, or `both`? Determines ESLint globals.
2. **Package manager**: default `npm`. Only switch to `yarn` or `pnpm` if user explicitly says so.

Don't ask about anything else — pick the canonical config and move on.

## Pre-flight

1. Verify you're in a directory cloned from `cvc-app-template` — check that `scripts/check-patterns.sh` and `CLAUDE.md` exist at the repo root. If not, stop and explain to the user.
2. Check if `package.json` already exists. If yes, you'll augment it; if no, you'll create it.
3. Check if `.husky/` already exists. If yes, append to existing hooks rather than overwriting.

## Procedure

### Step 1 — Initialize `package.json` (if needed)

If `package.json` does not exist, create it:

```bash
npm init -y
```

Then edit it to set `"type": "module"` and `"private": true`.

### Step 2 — Install dev dependencies

**Important: pin ESLint to `^9`.** `eslint-plugin-import` doesn't support ESLint 10 yet, and Vite scaffolds with v10. Without the pin, `npm install` fails with `ERESOLVE`.

```bash
npm install -D \
  husky \
  lint-staged \
  "eslint@^9" \
  "@eslint/js@^9" \
  typescript-eslint \
  @typescript-eslint/eslint-plugin \
  @typescript-eslint/parser \
  eslint-plugin-sonarjs \
  eslint-plugin-import \
  globals \
  prettier \
  typescript \
  vitest \
  @vitest/coverage-v8 \
  secretlint \
  @secretlint/secretlint-rule-preset-recommend
```

For the dep-vuln gate, `osv-scanner` is a Go binary (not on npm). It needs to be available in the dev container at commit time. The skill installs it automatically via the **flavor-tooling hooks anchor** in `post-create.sh` (see Step 8) — no host install required.

### Step 3 — Write `eslint.config.js`

Write this file at the repo root (adapt the globals based on the runtime decision):

```js
import globals from "globals";
import pluginJs from "@eslint/js";
import tseslint from "typescript-eslint";
import sonarjs from "eslint-plugin-sonarjs";
import importPlugin from "eslint-plugin-import";

export default [
  {
    ignores: [
      "**/node_modules/**",
      "**/dist/**",
      "**/build/**",
      "**/coverage/**",
      "**/*.min.*",
      "**/*.d.ts",
    ],
  },
  {
    languageOptions: {
      globals: {
        // PICK BASED ON RUNTIME DECISION:
        // browser: { ...globals.browser }
        // node:    { ...globals.node }
        // both:    { ...globals.browser, ...globals.node }
        ...globals.node,
      },
      ecmaVersion: "latest",
      sourceType: "module",
    },
    plugins: { sonarjs, import: importPlugin },
  },
  pluginJs.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["src/**/*.ts", "src/**/*.tsx"],
    rules: {
      // File and function size
      "max-lines": ["error", { max: 300, skipBlankLines: true, skipComments: true }],
      "max-lines-per-function": ["error", { max: 60, skipBlankLines: true, skipComments: true, IIFEs: true }],

      // Logical complexity
      "complexity": ["error", 12],
      "max-depth": ["error", 4],
      "max-nested-callbacks": ["error", 3],
      "max-params": ["error", 4],
      "max-statements": ["error", 25],

      // Refactor pressure
      "sonarjs/cognitive-complexity": ["error", 15],
      "sonarjs/no-duplicated-branches": "error",
      "sonarjs/no-identical-functions": "error",

      // Modularity
      "import/max-dependencies": ["error", { max: 25, ignoreTypeImports: true }],
      "import/no-cycle": "warn",

      // TS strictness
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_", varsIgnorePattern: "^_" }],
      "@typescript-eslint/no-explicit-any": "warn",
    },
  },
];
```

### Step 4 — Write `tsconfig.json`

If not present:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx"
  },
  "include": ["src/**/*"]
}
```

Drop `jsx` if the project isn't React. Adjust `target`/`module` per runtime.

### Step 5 — Write `.secretlintrc.json`

```json
{
  "rules": [
    {
      "id": "@secretlint/secretlint-rule-preset-recommend"
    }
  ]
}
```

### Step 6 — Write `.osv-scanner.toml`

```toml
# Add vulnerability IDs to ignore here with a written reason.
# [[IgnoredVulns]]
# id = "GHSA-xxxx-xxxx-xxxx"
# reason = "Not applicable: affected codepath is server-only and we run client-only"
```

### Step 7 — Add scripts and `lint-staged` config to `package.json`

Merge these into `package.json` (preserve any existing entries):

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
    "**/*.{ts,tsx,js,jsx,mjs,cjs}": [
      "npx secretlint --maskSecrets",
      "npx eslint --max-warnings 0 --no-warn-ignored"
    ],
    "**/package-lock.json": [
      "osv-scanner --lockfile"
    ]
  }
}
```

### Step 8 — Wire husky

```bash
npx husky init
```

That creates `.husky/pre-commit` with a default `npm test` line. Replace its contents with:

```bash
npx lint-staged
bash scripts/check-patterns.sh
```

`scripts/check-patterns.sh` must run **last** so it gates after all the auto-checkable hooks have passed.

### Step 8b — Patch `post-create.sh` to install osv-scanner in-container

`osv-scanner` is a Go binary, not on npm. The `lint-staged` hook in Step 7 calls `osv-scanner --lockfile`, so the binary must be on `PATH` inside the dev container before any commit. Patch `.devcontainer/post-create.sh` by inserting the following block **between** the `flavor-tooling hooks` anchor markers (the anchor markers exist in every fresh `cvc-app-template` clone):

```bash
# Install osv-scanner (Go binary, not on npm). Idempotent — skipped if
# already present. Required by the TS-flavor lockfile-vuln gate.
if [ -f package-lock.json ] && ! command -v osv-scanner >/dev/null 2>&1; then
  echo -e "${cyan}→ Installing osv-scanner (TS-flavor lockfile gate)...${reset}"
  arch=$(uname -m)
  case "$arch" in
    x86_64)  osv_asset="osv-scanner_linux_amd64" ;;
    aarch64) osv_asset="osv-scanner_linux_arm64" ;;
    *) echo "  WARN: unknown arch '$arch' — install osv-scanner manually" >&2; osv_asset="" ;;
  esac
  if [ -n "$osv_asset" ]; then
    sudo curl -fsSL -o /usr/local/bin/osv-scanner \
      "https://github.com/google/osv-scanner/releases/latest/download/${osv_asset}"
    sudo chmod +x /usr/local/bin/osv-scanner
    osv-scanner --version
  fi
fi
```

Find the marker `# === BEGIN flavor-tooling hooks (appended by setup-*-flavor skills) ===` and insert the block above the `# === END flavor-tooling hooks ===` line. Don't replace existing lines — append.

### Step 9 — Verify

Stage a trivial change and attempt a commit:

```bash
echo "// touched" >> src/index.ts   # or any staged file
git add .
git commit -m "test: verify pre-commit pipeline"
```

You should see:

1. `lint-staged` running secretlint + eslint on staged files
2. osv-scanner running on the lockfile (if present)
3. The pattern-check gate printing its banner and blocking the commit

That's the expected end-state — the gate refuses because `.patterns-checked` doesn't exist yet. Tell the user:

> "TS flavor wired. Try a commit — pre-commit will run lint-staged then block on the pattern gate. Run `/check-patterns` to audit and stamp, then retry the commit."

## What you've added

```
package.json                       ← scripts + devDeps + lint-staged config
package-lock.json                  ← (auto)
eslint.config.js                   ← complexity gates
tsconfig.json
.secretlintrc.json
.osv-scanner.toml
.husky/pre-commit                  ← runs lint-staged → check-patterns gate
.devcontainer/post-create.sh       ← patched: osv-scanner install block in
                                     the flavor-tooling anchor section
```

## What NOT to do

- **Don't soften the complexity gates** ("complexity" 12, "max-lines" 300, etc.) to make legacy code pass. Refactor instead.
- **Don't replace `bash scripts/check-patterns.sh` with anything else** in `.husky/pre-commit`. The gate script is the canonical artifact.
- **Don't combine this skill with a stack-specific setup** (Supabase, Vite, etc.) in one go. Run this first, then handle stack work as a separate operation.
- **Don't add `husky install` to `prepare` manually** — `npx husky init` already wires it.
