# cvc-app-template

A Claude-driven starting point for building internal-tool apps at CVC. Clone this, then ask Claude Code to bootstrap your chosen stack on top.

> **Status:** v0.5 — universal harness + language flavors (TS, Python) + stack skills (Vite/React, Supabase) + Claude GitHub Action. Validated end-to-end on a React + Supabase test once. Further stacks (FastAPI, FastMCP, etc.) and tested-via-CI fixtures are pending.

## What's in v0.5

The base ships only the rules and the universal tools; Claude picks the language-specific tooling at bootstrap time and patches it into the harness. Below is what a fresh **React + Supabase** project actually contains after all three skills run.

### Dev environment

| What | Detail |
|---|---|
| Base image | `mcr.microsoft.com/devcontainers/typescript-node:1-22-bookworm` (Node 22.16) |
| Features | `common-utils:2` (zsh + Oh My Zsh), `git:1` (latest), `github-cli:1` (`gh`), `docker-outside-of-docker:1` (host docker socket — DooD) |
| Network | `--network=host` so localhost in the container reaches Supabase's host-published ports |
| Workspace mount | `${localWorkspaceFolder}` → identical path in container (required for DooD bind-mounts back into sibling containers) |
| User | `node` (UID 1000) — matches typical host user |
| Cross-platform | Validated on Docker Desktop for Mac (arm64) + Windows (WSL2). JS-debug auto-attach disabled to avoid `bootloader.js` crashes across rebuilds. |

### Pre-commit pipeline (4 gates, wired by `setup-ts-flavor`)

| Gate | Tool | Version | Scope |
|---|---|---|---|
| Hygiene | `git diff --check --cached` | git built-in | Trailing whitespace, mixed tabs/spaces, merge markers across all staged files |
| Secrets | `gitleaks protect --staged` | v8.21.2 pinned (Go binary) | API keys, tokens, credentials — all staged files |
| Lint + complexity | `eslint` + `eslint-plugin-sonarjs` + `eslint-plugin-import` | `^9` pinned | `max-lines: 300`, `max-lines-per-function: 60`, `complexity: 12`, `max-depth: 4`, `max-statements: 25`, `sonarjs/cognitive-complexity: 15`, `no-duplicated-branches`, `no-identical-functions`, `import/max-dependencies: 25`, `import/no-cycle: warn` |
| Format | `prettier` | `^3` | `.json`, `.md`, `.yaml`, `.css`, `.html` files |
| Dep vulns | `osv-scanner --lockfile` | v1.9.2 pinned (Go binary) | `package-lock.json` against the OSV DB |
| Patterns audit | `scripts/check-patterns.sh` | custom | **Refuses commit until Claude has audited the staged diff via `/check-patterns`.** Stamp is sha256-bound to the staged diff — re-staging or `lint-staged --fix` mutations invalidate it. |

Orchestrated by `husky` + `lint-staged@^16` (Node 22.16 engine-compat).

### Claude skills

| Skill | Lines | Purpose |
|---|---|---|
| `check-patterns` | 79 | Pre-commit audit for duplicated logic + unnecessary fallbacks. The hash-bound gate above is its enforcement arm. |
| `setup-ts-flavor` | 147 | Installs the 4-gate pipeline for TS/JS. Detects Vite+React and uses the React-aware ESLint config when present. |
| `setup-python-flavor` | 77 | Same contract for Python via `pre-commit` framework + ruff + mypy + pytest+coverage. *Not yet validated end-to-end.* |
| `setup-vite-react-stack` | 137 | Scaffolds Vite + React + TS, port 8080, `@` alias, SWC plugin, Tailwind v4 via `@tailwindcss/vite`, `react-router-dom`, and the standard Supabase auth glue (`client.ts` + `ProtectedRoute` + `LoginPage` + `Dashboard`). |
| `setup-supabase-stack` | 152 | `supabase init`, foundation migration + seed (admin/member test users), devcontainer patches for ports 54321–54324 + `supabase start` on rebuild. |

### Attribution + telemetry

| What | Detail |
|---|---|
| [`git-ai`](https://usegitai.com) | v1.4.11 pinned (Go binary). Installed by base `post-create.sh` — universal, every CVC app. Auto-attributes each committed line to the AI agent + prompt; persisted via Git Notes; survives rebases / merges / cherry-picks. Local-first SQLite; no telemetry leaves the container without team-cloud opt-in. |
| `/who-wrote-this <file>` | Claude slash command wrapping `git ai blame`. Useful in PR review (*"this PR is 80% AI — extra eyes"*) and post-hoc bug audits. |

### GitHub integration

| What | Detail |
|---|---|
| `.github/workflows/claude.yml` | Claude Code Action — `@claude` in issue body/title/comment or PR review fires Claude on a GitHub Actions runner. Pushes to `claude/...` branch + posts a PR-creation link (or comments for question-shaped tasks). Default auth via `ANTHROPIC_API_KEY` secret; OAuth (Pro/Max subscription quota) supported as the commented alternative. |

### Foundation database schema (`setup-supabase-stack`)

| Object | Purpose |
|---|---|
| `app_role` enum | `admin` / `member` |
| `user_roles` | FK to `auth.users`; one role per user |
| `user_profiles` | FK to `auth.users`; `display_name`, auto-updated `updated_at` |
| `audit_events` | Append-only audit log; before/after JSONB snapshots; only written by `log_audit_event()` trigger |
| `audit_redactions` | Opt-in column allowlist — declare `(table_name, column_name, reason)` for secrets/PII; `audit_redact()` strips them before logging |
| `has_role(uid, role)` | SECURITY DEFINER + pinned `search_path` + **`REVOKE EXECUTE … FROM PUBLIC`**. Internal-only — RLS policies use it; clients can't probe arbitrary users' roles. |
| `user_has_role(role)` | Public-facing wrapper; always uses `auth.uid()`. The function authenticated clients call. |
| `handle_new_user()` | Trigger on `auth.users` INSERT — auto-provisions `user_roles` + `user_profiles` in the same transaction |
| RLS | Default-deny on all four public tables. Self-read on own role/profile; admin sees all; `audit_events` writable only via SECURITY DEFINER trigger. |

### Conventions

- `.prettierrc`: `{ singleQuote: true, trailingComma: "all", printWidth: 100 }` — required, or default prettier double-quotes break the first commit.
- `.prettierignore`: skips JSONC files (`devcontainer.json`, `tsconfig*.json`) and `*.toml` — prettier 3.x can't parse either.
- Two anchor blocks in `post-create.sh` (`flavor-tooling hooks` + `stack-specific hooks`) define where skills append. Composable across multiple skills.

What does **not** ship out of the box: framework code, `package.json`, `pyproject.toml`, `.pre-commit-config.yaml`. The harness is the contract; tooling is selected at bootstrap.

## Quick start

```bash
# 1. Clone as your project starting point
git clone https://github.com/<org>/cvc-app-template my-new-app
cd my-new-app

# 2. Open in VS Code → Reopen in Container
code my-new-app

# 3. Inside the container, open Claude Code
claude
> "set me up for React + Supabase"     # or whatever stack
```

Claude will then:

1. Read `CLAUDE.md` to understand the hooks contract
2. Pick the language-idiomatic pre-commit framework (husky + lint-staged for TS, the `pre-commit` framework for Python, etc.)
3. Install and configure the gates required by the contract (secrets, dep vulns, hygiene, patterns, lint+complexity)
4. Wire `scripts/check-patterns.sh` into the gate so the `check-patterns` Claude skill is enforced on every commit
5. Scaffold the stack itself

### Example prompt: minimal React + Supabase app

Open Claude Code in an empty directory on your machine and paste:

```
Set me up a tiny internal-tool starter. Backend-less, Supabase auth, React/Vite SPA — nothing fancy.

Use `sanagnoscvc/cvc-app-template` (private repo) as the base. It ships Claude-runnable skills (`setup-vite-react-stack`, `setup-ts-flavor`, `setup-supabase-stack`) and a `CLAUDE.md` explaining how they compose. Clone it into `./my-app`, read the `CLAUDE.md` before touching anything, then run the skills in whatever order it recommends.

What I need in the app:
- Login page (email + password)
- Protected `/` route — dashboard that shows "Welcome, [display_name]" pulled from `public.user_profiles`
- Logout button

Should work end-to-end with the seeded `admin@localhost.local` / `admin1234` user once I rebuild the devcontainer in VS Code.

Pre-commit pipeline gates on lint + secrets + dep vulns + a pattern audit. Don't `--no-verify`. If anything in the skills is ambiguous or broken, surface it — we want the harness improved, not papered over.
```

Claude will clone the template, follow the three skills in the recommended order, scaffold the app, and tell you to rebuild the dev container. After the rebuild, `npm run dev` → http://localhost:8080 → log in as `admin@localhost.local` / `admin1234` → land on the dashboard with "Welcome, Admin User".

If anything goes sideways, Claude is instructed to **surface the gap rather than paper over it** — please copy that feedback into a GitHub issue against this repo so the skills can be tightened.

## The hooks contract

Every CVC app committed from a clone of this template runs the same five gates on every commit:

| Gate                          | Purpose                                                                                                   |
| ----------------------------- | --------------------------------------------------------------------------------------------------------- |
| Secret scanning               | Catches API keys, tokens, credentials in staged files                                                     |
| Dependency vulnerability scan | Blocks commits that introduce known-vulnerable deps                                                       |
| File hygiene                  | Trailing whitespace, JSON/YAML/TOML syntax, large files, merge markers                                    |
| **Pattern audit**             | Refuses to commit until Claude has audited the staged diff for duplicated logic and unnecessary fallbacks |
| Lint + complexity gates       | Language-specific: file size, function complexity, nesting depth                                          |

The first four are universal. The fifth is set up to match your language. See [`CLAUDE.md`](./CLAUDE.md) for the full contract and the per-language recommendations Claude uses.

## How the pattern audit works

1. You stage changes and run `git commit`.
2. The pre-commit pipeline runs all gates.
3. The `check-patterns` gate refuses the commit unless a `.patterns-checked` stamp file exists.
4. To pass the gate: run `/check-patterns` in Claude Code. The skill audits the staged diff, reports duplicated logic or unnecessary fallbacks if any, and writes the stamp file if clean.
5. Re-run `git commit`. The stamp is consumed (deleted) so the next commit cycle has to audit again.

This forces every commit through a quality pass without requiring you to remember.

## Project layout

```
cvc-app-template/
├── .gitignore                            ← multi-language defaults
├── .devcontainer/
│   ├── devcontainer.json                 ← DooD + --network=host + path-aligned mount
│   └── post-create.sh                    ← stack-agnostic; npm/supabase only if present
├── .github/workflows/
│   └── claude.yml                        ← Claude GitHub Action — @claude in issues/PRs
├── scripts/
│   └── check-patterns.sh                 ← gate script (blocks commit until stamp exists)
├── .claude/
│   ├── skills/
│   │   ├── check-patterns/SKILL.md           ← the pre-commit audit skill
│   │   ├── setup-ts-flavor/SKILL.md          ← TS/JS bootstrap (husky + lint-staged + eslint)
│   │   ├── setup-python-flavor/SKILL.md      ← Python bootstrap (pre-commit + ruff + uv)
│   │   ├── setup-vite-react-stack/           ← Vite + React + TS stack: port + alias + Tailwind v4 + Supabase auth glue
│   │   │   ├── SKILL.md
│   │   │   └── assets/{vite.config.ts,main.tsx,index.css,client.ts,ProtectedRoute.tsx,LoginPage.tsx,Dashboard.tsx}
│   │   └── setup-supabase-stack/             ← Supabase stack: migrations + RLS + devcontainer patches
│   │       ├── SKILL.md
│   │       └── assets/{foundation.sql,seed.sql}
│   └── commands/check-patterns.md        ← /check-patterns slash command
├── CLAUDE.md                             ← Claude's constitution + hooks contract
└── README.md                             ← this file
```

## Triggering Claude from GitHub

The shipped `.github/workflows/claude.yml` wires up the [Claude GitHub Action](https://github.com/anthropics/claude-code-action). Trigger by mentioning **`@claude`** in:

- an issue body or title (at open time, or by editing afterward)
- a comment on an issue or PR
- a PR review body

Claude runs on a GitHub Actions runner. Depending on the task, it may push commits to a `claude/...` branch and post a comment with a link to create the PR, or just reply in-thread for question-shaped tasks. (Exact behavior depends on the action version + Anthropic's current defaults — check the linked docs if you need precise semantics.)

**One-time setup per repo:**

1. Install the [Claude GitHub App](https://github.com/apps/claude)
2. Get an Anthropic API key at [console.anthropic.com](https://console.anthropic.com/settings/keys). Add it as a repo secret named `ANTHROPIC_API_KEY` at `Settings → Secrets and variables → Actions`. _(Pro/Max subscribers can use OAuth instead — see the commented section in `.github/workflows/claude.yml`.)_
3. Push `main`. Claude is now triggerable.

Billed as GitHub Actions minutes + Anthropic API tokens (or subscription quota if using OAuth).

## Prerequisites

- `git`
- Claude Code (for the `check-patterns` skill and bootstrapping)

Everything else — the pre-commit framework, language tooling, hook implementations — is installed by Claude at bootstrap time based on your stack choice.
