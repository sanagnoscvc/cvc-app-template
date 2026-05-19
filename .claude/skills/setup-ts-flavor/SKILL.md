---
name: setup-ts-flavor
description: |
  **TypeScript/JavaScript Flavor Bootstrap**: Wires the CLAUDE.md hooks contract
  into a TS/JS project using husky + lint-staged (npm-native idiom). Installs
  ESLint complexity gates, prettier, vitest. Patches post-create.sh to install
  gitleaks (broad secret-scan gate) and osv-scanner (lockfile-vuln gate) inside
  the dev container. Wires the check-patterns gate into the husky pre-commit
  hook. If the project also has Vite + React (detected via vite.config.ts),
  preserves the React-specific ESLint plugins instead of overwriting them.
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
  "lint-staged@^16" \
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
  @vitest/coverage-v8
```

**Note on `lint-staged@^16`**: v17+ requires Node `>=22.22.1`, but the dev container's `typescript-node:1-22-bookworm` base image currently ships Node `22.16`. v16 is the latest that's engine-compatible. Bump when the base image moves past 22.22.

Two language-agnostic tools are installed via the **flavor-tooling hooks anchor** in `.devcontainer/post-create.sh` (see Step 8b) — both are Go binaries, not on npm:

- **`gitleaks`** — broad secret scanner that runs on *every* staged file (not just JS/TS, so it catches secrets in `.env`, YAML, JSON, etc.).
- **`osv-scanner`** — dep-vuln scan against the OSV database, runs on lockfiles.

We deliberately do **not** use `secretlint` (npm package) — its default config only scans JS/TS by glob and would leave secrets in non-JS files undetected.

### Step 3 — Write `eslint.config.js`

**Detection first.** Check whether Vite + React are already scaffolded (typically via `setup-vite-react-stack` running before this skill):

```bash
has_react=0
if grep -q '"vite"' package.json 2>/dev/null && grep -q '"react"' package.json 2>/dev/null; then
  has_react=1
fi
```

Pick the config variant accordingly and write `eslint.config.js` at the repo root.

#### Variant A — vanilla TS (no React)

Use when `has_react=0` (pure TS library, CLI, Node service, etc.):

```js
import globals from "globals";
import pluginJs from "@eslint/js";
import tseslint from "typescript-eslint";
import sonarjs from "eslint-plugin-sonarjs";
import importPlugin from "eslint-plugin-import";

export default [
  {
    ignores: [
      "**/node_modules/**", "**/dist/**", "**/build/**",
      "**/coverage/**", "**/*.min.*", "**/*.d.ts",
    ],
  },
  {
    languageOptions: {
      globals: { ...globals.node },   // swap to browser / both based on runtime
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
      "max-lines": ["error", { max: 300, skipBlankLines: true, skipComments: true }],
      "max-lines-per-function": ["error", { max: 60, skipBlankLines: true, skipComments: true, IIFEs: true }],
      "complexity": ["error", 12],
      "max-depth": ["error", 4],
      "max-nested-callbacks": ["error", 3],
      "max-params": ["error", 4],
      "max-statements": ["error", 25],
      "sonarjs/cognitive-complexity": ["error", 15],
      "sonarjs/no-duplicated-branches": "error",
      "sonarjs/no-identical-functions": "error",
      "import/max-dependencies": ["error", { max: 25, ignoreTypeImports: true }],
      "import/no-cycle": "warn",
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_", varsIgnorePattern: "^_" }],
      "@typescript-eslint/no-explicit-any": "warn",
    },
  },
];
```

#### Variant B — Vite + React

Use when `has_react=1`. Same complexity gates, but adds `eslint-plugin-react-hooks` + `eslint-plugin-react-refresh` (Vite already installed these in your `setup-vite-react-stack` run; this config wires them up rather than dropping them):

```js
import globals from "globals";
import pluginJs from "@eslint/js";
import tseslint from "typescript-eslint";
import sonarjs from "eslint-plugin-sonarjs";
import importPlugin from "eslint-plugin-import";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";

export default [
  {
    ignores: [
      "**/node_modules/**", "**/dist/**", "**/build/**",
      "**/coverage/**", "**/*.min.*", "**/*.d.ts",
    ],
  },
  {
    languageOptions: {
      globals: { ...globals.browser },
      ecmaVersion: "latest",
      sourceType: "module",
    },
    plugins: { sonarjs, import: importPlugin },
  },
  pluginJs.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["src/**/*.ts", "src/**/*.tsx"],
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],

      "max-lines": ["error", { max: 300, skipBlankLines: true, skipComments: true }],
      "max-lines-per-function": ["error", { max: 60, skipBlankLines: true, skipComments: true, IIFEs: true }],
      "complexity": ["error", 12],
      "max-depth": ["error", 4],
      "max-nested-callbacks": ["error", 3],
      "max-params": ["error", 4],
      "max-statements": ["error", 25],
      "sonarjs/cognitive-complexity": ["error", 15],
      "sonarjs/no-duplicated-branches": "error",
      "sonarjs/no-identical-functions": "error",
      "import/max-dependencies": ["error", { max: 25, ignoreTypeImports: true }],
      "import/no-cycle": "warn",
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

### Step 5 — Write `.prettierrc`

Critical — without this file, `prettier --check` (run inside `lint-staged`, Step 7) fails on every first commit because:

- Default prettier wants double quotes
- The skill assets (and CVC convention) use single quotes
- So a clean install with default prettier blocks every commit until someone adds `.prettierrc`

Ship it with the skill:

```json
{
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100
}
```

(Previously this skill's Step 5 was a `.secretlintrc.json` write — secretlint is no longer used, gitleaks replaces it in Step 8b.)

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
      "npx eslint --max-warnings 0 --no-warn-ignored"
    ],
    "**/*.{json,md,yaml,yml,css,html}": [
      "npx prettier --check"
    ],
    "**/package-lock.json": [
      "osv-scanner --lockfile"
    ]
  }
}
```

Note: secret scanning is **not** in `lint-staged` — `gitleaks` runs in `.husky/pre-commit` directly (Step 8) so it sees the full staged set, not lint-staged's per-glob slices.

Important: **don't add `toml` to the prettier glob.** Prettier 3.x ships no TOML parser; `prettier --check` errors with *"No parser could be inferred"* on `.osv-scanner.toml` (this skill's Step 6) and `supabase/config.toml` (supabase init's output). Every first commit would die. If you genuinely want formatted TOML, add `prettier-plugin-toml` to devDeps and wire it in `.prettierrc` — heavier than worth it for two configs that aren't hand-edited often.

### Step 8 — Wire husky

```bash
npx husky init
```

That creates `.husky/pre-commit` with a default `npm test` line. Replace its contents with:

```bash
# 1. File-hygiene gate. `git diff --check --cached` flags trailing
#    whitespace, mixed tabs/spaces, AND unresolved merge markers in
#    staged files. `--no-pager` so the output doesn't get piped through
#    `less` (which forces the user to manually `q` out of it before the
#    hook continues to the next step).
if ! git --no-pager diff --check --cached; then
  echo "" >&2
  echo "✗ Whitespace errors or merge markers in staged files (see above)." >&2
  echo "  Most common fix:  npx prettier --write <file>  &&  git add <file>" >&2
  exit 1
fi

# 2. Broad secret scanning across ALL staged files (not just JS/TS).
gitleaks protect --staged --no-banner --verbose

# 3. Language-specific lint + formatting + lockfile vuln scan
#    (configured in package.json's "lint-staged" block).
npx lint-staged

# 4. Pattern audit gate — hash-bound to the staged diff after lint-staged.
#    Re-runs are required if lint-staged --fix mutates anything.
bash scripts/check-patterns.sh
```

The patterns gate must run **last** so it stamps a hash of the final, post-`lint-staged` staged diff. Anything that mutates the staged set after the audit invalidates the stamp.

### Step 8b — Patch `post-create.sh` to install Go-binary gate tools

Two Go binaries (`gitleaks`, `osv-scanner`) drive the flavor's secret + dep-vuln gates. Neither is on npm; both need to be on `PATH` inside the dev container before any commit. Patch `.devcontainer/post-create.sh` by inserting the block below **between** the `flavor-tooling hooks` anchor markers.

**Idempotency check first** — if the sentinel comment `# ts-flavor-tools` is already present, do nothing (the block has been applied before). Otherwise insert it.

```bash
# ts-flavor-tools — install Go-binary gate tools (gitleaks, osv-scanner).
# Both are pinned. Idempotent: skipped if already present on PATH.
GITLEAKS_VERSION=8.21.2
OSV_SCANNER_VERSION=1.9.2

arch=$(uname -m)
case "$arch" in
  x86_64)  gl_arch="x64";  osv_asset="osv-scanner_linux_amd64" ;;
  aarch64) gl_arch="arm64"; osv_asset="osv-scanner_linux_arm64" ;;
  *) echo "  WARN: unknown arch '$arch' — install gitleaks + osv-scanner manually" >&2;
     gl_arch=""; osv_asset="" ;;
esac

if [ -n "$gl_arch" ] && ! command -v gitleaks >/dev/null 2>&1; then
  echo -e "${cyan}→ Installing gitleaks v${GITLEAKS_VERSION} (TS-flavor secret-scan gate)...${reset}"
  tmpdir=$(mktemp -d)
  curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz" \
    | tar -xz -C "$tmpdir" gitleaks
  sudo mv "$tmpdir/gitleaks" /usr/local/bin/gitleaks
  rm -rf "$tmpdir"
fi

if [ -n "$osv_asset" ] && ! command -v osv-scanner >/dev/null 2>&1; then
  echo -e "${cyan}→ Installing osv-scanner v${OSV_SCANNER_VERSION} (TS-flavor lockfile gate)...${reset}"
  sudo curl -fsSL -o /usr/local/bin/osv-scanner \
    "https://github.com/google/osv-scanner/releases/download/v${OSV_SCANNER_VERSION}/${osv_asset}"
  sudo chmod +x /usr/local/bin/osv-scanner
fi
```

Find the marker `# === BEGIN flavor-tooling hooks (appended by setup-*-flavor skills) ===` and insert this block above the `# === END flavor-tooling hooks ===` line. **Pin versions** as shown above — never `latest`. To bump, update `GITLEAKS_VERSION` / `OSV_SCANNER_VERSION` in the block.

### Step 9 — Format the working tree

Before the user attempts a commit, run prettier across the project so the lint-staged `prettier --check` doesn't block on pre-existing scaffold drift (Vite's `tsconfig.json` ships without trailing newlines, etc.):

```bash
npx prettier --write \
  'src/**/*.{ts,tsx,css,json}' \
  'index.html' 'package.json' 'tsconfig*.json' \
  'eslint.config.js' 'vite.config.ts' 'README.md' 2>/dev/null || true
```

`|| true` because not all paths will exist in every project (e.g. no `vite.config.ts` in a Node-only project). Prettier only formats what it finds.

### Step 10 — Verify

The Go-binary gates (gitleaks, osv-scanner) are installed by `post-create.sh` inside the dev container on rebuild — they're **not** on the host (macOS, Linux WSL, etc.). So **don't try to run `git commit` from the host** as a verification step; it'll fail with "command not found: gitleaks." Instead:

- Run `npm run lint` — should pass (eslint config + complexity gates).
- Run `npm run build` — should compile cleanly.
- Run `npx prettier --check '**/*.{ts,tsx,json,md,css}' 'eslint.config.js'` — should report "All matched files use Prettier code style!"

Tell the user:

> "TS flavor wired. Verify on host: `npm run lint && npm run build` should both pass. Don't attempt a commit on the host — gitleaks + osv-scanner only install inside the dev container on rebuild. After the rebuild, the first commit inside the container will exercise all four pre-commit gates; the pattern gate will refuse until `/check-patterns` stamps."

## What you've added

```
package.json                       ← scripts + devDeps + lint-staged config
package-lock.json                  ← (auto)
eslint.config.js                   ← complexity gates (+ React plugins if Vite)
tsconfig.json                      ← (only if absent — Vite's takes precedence)
.osv-scanner.toml
.prettierrc                        ← singleQuote + trailingComma + printWidth
                                     (CVC convention; without this, prettier
                                     --check fails on every first commit)
.husky/pre-commit                  ← 4-step: merge-markers → gitleaks →
                                     lint-staged → patterns gate
.devcontainer/post-create.sh       ← patched: pinned gitleaks + osv-scanner
                                     install block in the flavor-tooling
                                     anchor section
```

## What NOT to do

- **Don't soften the complexity gates** ("complexity" 12, "max-lines" 300, etc.) to make legacy code pass. Refactor instead.
- **Don't replace `bash scripts/check-patterns.sh` with anything else** in `.husky/pre-commit`. The gate script is the canonical artifact.
- **Don't combine this skill with a stack-specific setup** (Supabase, Vite, etc.) in one go. Run this first, then handle stack work as a separate operation.
- **Don't add `husky install` to `prepare` manually** — `npx husky init` already wires it.
