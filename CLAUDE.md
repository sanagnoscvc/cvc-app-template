# CLAUDE.md

You're working in `cvc-app-template` — a Claude-driven starting point for building CVC internal-tool apps. This file is your constitution.

## What this repo is (and isn't)

A **stack-agnostic harness**, not an app. No framework picked, no language assumed. A developer clones it as the starting point of a new project, then asks you to bootstrap their chosen stack on top.

What ships out of the box:

- **Dev container** (`.devcontainer/`) — Node 22 base + DooD socket + `--network=host` + path-aligned workspace mount. Stack-agnostic; post-create only installs npm deps if `package.json` exists and only starts Supabase if `supabase/config.toml` exists.
- The `check-patterns` skill + slash command + gate script — the discipline that catches duplicated logic and defensive fallbacks before they get committed
- The `setup-ts-flavor` and `setup-python-flavor` skills — invoke these when the user asks you to bootstrap a stack in the corresponding language
- The `.github/workflows/claude.yml` Claude GitHub Action — `@claude` triggers from issues/PRs
- This `CLAUDE.md` — the hooks contract you must satisfy when you bootstrap a stack
- A multi-language `.gitignore` baseline

What does **not** ship: any pre-commit framework, any language tooling, any dependency manifests. You wire those up at bootstrap time according to the user's stack.

## The hooks contract

Every commit, in every CVC app cloned from this template, **must** be gated by these checks:

| # | Category | What it does | Why |
|---|---|---|---|
| 1 | **Secret scanning** | Block API keys, tokens, credentials in staged files | Prevent credential leaks to git history |
| 2 | **Dependency vulnerability scanning** | Block commits introducing known-vulnerable deps | Stop CVEs at the source |
| 3 | **File hygiene** | No trailing whitespace, valid JSON/YAML/TOML, no merge markers, file-size limits | Clean diffs, no syntax foot-guns |
| 4 | **Pattern audit** (`check-patterns`) | Refuse commit until you've audited the staged diff for duplicated/defensive code | Highest-leverage Claude-discipline gate |
| 5 | **Lint + complexity gates** | Language-specific rules (file size, function complexity, nesting depth, etc.) | Stops monster files / functions before they grow |

The first four are universal — same intent across every CVC app. The fifth is language-specific and you set it up per the chosen flavor.

## When the user asks you to bootstrap a stack

Your job is to wire the contract above into whatever framework is idiomatic for their language. **Prefer invoking the skills below** — they encode the deterministic install + config steps so you don't re-derive them each session.

### Recommended order for compound stacks

When the user asks for something like *"React + Supabase"*, run skills in this order:

1. **Stack interface skill** — scaffolds the application framework (e.g. `setup-vite-react-stack` creates `package.json` + `vite.config.ts` + the React app skeleton).
2. **Flavor skill** — adds the harness (lint, hooks, complexity gates, secret scan). For TS/JS: `setup-ts-flavor`. For Python: `setup-python-flavor`. The flavor skill detects what the stack skill already installed (e.g. Vite + React's ESLint plugins) and composes rather than overwriting.
3. **Stack storage / backend skill** — wires the data layer (e.g. `setup-supabase-stack` runs `supabase init` + drops the foundation migration + patches devcontainer for ports).

Why this order: the flavor skill's ESLint config branches on whether React is present in `package.json`. If the flavor runs first, it writes a non-React config; the stack skill then has to either re-merge React rules or you ship without them. Doing stack-first avoids that whole class of issue.

### TypeScript / JavaScript

→ **Invoke the `setup-ts-flavor` skill** (`.claude/skills/setup-ts-flavor/SKILL.md`).

Summary of what it sets up: `husky` + `lint-staged` (npm-native), `secretlint`, `osv-scanner`, `eslint` with complexity gates (`sonarjs`, `max-lines`, `complexity`, `max-statements`), `prettier`, `vitest`. Wires `bash scripts/check-patterns.sh` as the last entry in `.husky/pre-commit`.

### Python

→ **Invoke the `setup-python-flavor` skill** (`.claude/skills/setup-python-flavor/SKILL.md`).

Summary of what it sets up: the [`pre-commit`](https://pre-commit.com/) framework, `ruff` (lint + complexity + format), `mypy`, `pytest` with coverage, `gitleaks` + `osv-scanner` via their pre-commit hooks. Wires the check-patterns gate as a `local` hook. Defaults to `uv` for package management, Python 3.12.

### Mixed (e.g. TS frontend + Python backend in one repo)

Use the `pre-commit` framework as the shared orchestrator. Don't try to layer husky on top of pre-commit. Apply the Python flavor skill first, then add the TS-specific hooks (ESLint, secretlint via `npx`) into the same `.pre-commit-config.yaml`.

### Other languages (Rust, Go, etc.)

Use the `pre-commit` framework as the default — it has hook ecosystems for most languages. Adapt the Python flavor's config shape: keep the universal hooks (gitleaks, osv-scanner, file hygiene, check-patterns), swap ruff for the language-appropriate lint+complexity tool (clippy for Rust, golangci-lint for Go). No flavor skill exists for these yet; document what you set up so a skill can be extracted later.

## How you wire the `check-patterns` gate

The script `scripts/check-patterns.sh` is the canonical gate — don't rewrite it. Just call it from the chosen framework's pre-commit entry point:

- **husky**: add `bash scripts/check-patterns.sh` to `.husky/pre-commit` as the last line
- **pre-commit framework**: add a `local` hook entry that runs `bash scripts/check-patterns.sh`

Either way, the script blocks the commit until `.patterns-checked` exists. You produce that stamp by actually running `/check-patterns` and finding the staged diff clean.

## Commit discipline (non-negotiable)

**NEVER use `--no-verify` when committing.** The pre-commit hooks exist for security and code quality. If a commit fails:

1. Attempt to fix the issues in the staged files.
2. If the issues cannot be resolved through code modifications, stop and explain the situation to the user.
3. Do not bypass hooks under any circumstances — they are a security and discipline requirement.
4. Do not change the git hooks that are in place without the user's explicit instruction.
5. You are responsible for fixing **ALL** issues discovered during commit checks — even if they exist in files you didn't modify or are unrelated to the work done in the current session. The goal is always a clean commit.

## Dev container threat model

The dev container is configured for the user's own development convenience, **not** as a security sandbox against malicious code:

- `~/.claude` and `~/.ssh` are bind-mounted from the host so Claude Code and `gh`/`git` work inside the container the same way they do on the host. Anything running in the container can read these.
- The host's Docker socket is mounted (DooD) — code in the container can launch sibling containers on the host's Docker.
- `npm install` runs automatically on container rebuild if `package.json` exists. This executes `postinstall` scripts in npm packages.

A malicious npm package's `postinstall` could read host credentials via the bind mounts and drive Docker via the socket. **This is the same exposure you'd have running `npm install` on the host directly** — the dev container is not stronger isolation, just a *consistency boundary* (same Node version, same system deps, same tooling for every teammate).

If you need stronger isolation for genuinely untrusted code (running an AI-generated script you don't trust, executing user-uploaded code, etc.), use a Vercel Sandbox, ephemeral cloud container, or VM — not this dev container.

When you bootstrap a stack, only add credentials the stack will actually use. e.g. `setup-supabase-stack` adds `SUPABASE_ACCESS_TOKEN` to `remoteEnv` because Supabase migrations against a linked remote project need it. Don't add credentials to the base for stacks that aren't wired.

## AI-code attribution (`git-ai`)

Every dev container has [`git-ai`](https://usegitai.com) installed (universal harness tool, not flavor-specific). It auto-attributes each line you commit to the agent + prompt that produced it, persisted via Git Notes and survives rebases/merges. Local-first — no telemetry leaves the container without explicit team-cloud opt-in.

Practical effect for you (Claude): your contributions are tracked. Treat that as accountability — when an engineer runs `/who-wrote-this` on a buggy line and it points at your prompt, the prompt becomes evidence. Quality matters because it's audited downstream.

## Stack skills and the modularity contract

The base harness is **stack-agnostic by design**. Supabase, FastAPI, Vite, FastMCP — none of those ship pre-wired. Each stack lives as its own self-contained skill at `.claude/skills/setup-<stack>-stack/`, invoked when the user asks for it.

When you invoke a stack skill, it's responsible for **all** of the following:

1. **Writing its own files** (e.g. `supabase/config.toml`, migrations, seed.sql).
2. **Patching `.devcontainer/devcontainer.json`** — merging additional `forwardPorts`, `portsAttributes`, `remoteEnv` keys. Don't overwrite existing entries; merge.
3. **Patching `.devcontainer/post-create.sh`** — appending steps **between** the appropriate anchor block. There are two:

   ```bash
   # === BEGIN flavor-tooling hooks (appended by setup-*-flavor skills) ===
   # ↑ flavor skills append here (e.g. installing osv-scanner binary)
   # === END flavor-tooling hooks ===

   # === BEGIN stack-specific hooks (appended by setup-*-stack skills) ===
   # ↑ stack skills append here (e.g. `supabase start`, framework boot)
   # === END stack-specific hooks ===
   ```

   Flavor-tooling runs first so stack hooks can rely on the tooling being in place. Multiple skills compose within each block by appending to it.
4. **Modifying `package.json` / `pyproject.toml`** to add stack-specific deps.
5. **Prompting the user to rebuild the dev container** at the end, so the devcontainer changes take effect.

Available stack skills:

- `setup-vite-react-stack` — Vite + React + TypeScript SPA. Port 8080, `@` alias, `@vitejs/plugin-react-swc`, Tailwind v4 via `@tailwindcss/vite`, react-router-dom, and (optionally) the standard Supabase auth glue (`client.ts` + `ProtectedRoute` + `LoginPage` + `Dashboard`).
- `setup-supabase-stack` — Supabase OLTP (auth + RLS + migrations skeleton). Adds Supabase CLI dep, scaffolds migrations + seed, patches devcontainer for ports 54321/54322/54323.

(More stack skills will be added as the supported set grows. If a user asks for a stack that has no skill, follow the same modularity contract by hand and document what you did so the work can be extracted into a skill later.)

## Running from the GitHub Action

`.github/workflows/claude.yml` wires up the Claude GitHub Action. When triggered by `@claude` in an issue or PR (or by an issue being opened/assigned), you run on a CI runner, commit to a `claude/...` branch, and open a PR back.

When running via the Action:

- The same hooks contract applies. Pre-commit will run on your commits. Don't `--no-verify`.
- If `.git/hooks/pre-commit` isn't installed in the runner's checkout (it usually isn't, since hooks aren't versioned), wire it up first: `pre-commit install` (if `pre-commit` framework) or `npx husky` (if husky). The flavor skills set this up automatically when the user calls them.
- For question-shaped tasks (no code change needed), just comment back on the issue instead of opening a PR.
- Surface decisions in the PR description, not as silent assumptions in code.

## What NOT to do

- **Don't soften the hooks contract** to make commits faster. Lower bars for "convenience" defeat the purpose.
- **Don't pick a framework the user's stack doesn't naturally use** (e.g. installing the `pre-commit` Python tool in a pure Node project just because you've used it before). Match the idiom.
- **Don't add application code to this template repo**. v0 is harness-only. Stack-specific work happens in repos *cloned from* this one, not inside it.
- **Don't add stack-specific files to the base harness** (e.g. supabase/, vite.config.ts, pyproject.toml). Those belong in skills, not in the base. The post-create.sh and devcontainer.json should stay stack-agnostic until a stack skill patches them.
- **Don't rewrite `check-patterns.sh` or the `check-patterns` skill**. They're the canonical artifacts. Wire them in; don't re-derive them.
