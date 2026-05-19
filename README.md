# cvc-app-template

A Claude-driven starting point for building internal-tool apps at CVC. Clone this, then ask Claude Code to bootstrap your chosen stack on top.

> **Status:** v0.5 — universal harness + language flavors (TS, Python) + stack skills (Vite/React, Supabase) + Claude GitHub Action. Validated end-to-end on a React + Supabase test once. Further stacks (FastAPI, FastMCP, etc.) and tested-via-CI fixtures are pending.

## What's in v0.5

A **stack-agnostic Claude harness** + a small set of language / stack bootstrap skills. Cloning gets you:

- **Dev container** (`.devcontainer/`) — Reopen in Container in VS Code and you get Node 22, gh CLI, zsh, the Docker socket (DooD), `--network=host` for Supabase compatibility, and a path-aligned workspace mount. Works on Mac and Windows Docker Desktop. Stack-agnostic: post-create only installs npm deps and starts Supabase if the workspace already has them.
- **AI-code attribution** ([`git-ai`](https://usegitai.com)) — installed by post-create. Auto-tags each commit with the AI agent + prompt that produced each line; survives rebases/merges via Git Notes. Local-first; no telemetry leaves the container. Use `/who-wrote-this <file>` from Claude Code, or `git ai blame <file>` directly. Useful for PR review (*"this PR is 80% AI — extra eyes"*) and post-hoc bug audits.
- **The `check-patterns` Claude skill** — encoded review pass Claude runs before each commit to flag duplicated logic and defensive shims
- **The `check-patterns.sh` gate script** — blocks commits until the audit has run (paired with whatever pre-commit framework Claude wires up for your stack)
- **Flavor bootstrap skills** — `setup-ts-flavor` and `setup-python-flavor` encode the deterministic install + config steps for each language family, so Claude doesn't re-derive them every time
- **Stack bootstrap skills** — modular, per-stack additions (`setup-supabase-stack` is the first). When invoked, a stack skill writes its own files, patches `devcontainer.json` + `post-create.sh` between the anchor comments, adds its deps, and prompts for a container rebuild. Multiple stack skills compose
- **Claude GitHub Action** (`.github/workflows/claude.yml`) — `@claude` in any issue or PR comment runs Claude on a CI runner: it commits to a `claude/...` branch and opens a PR back
- **`CLAUDE.md`** — Claude's constitution for working in CVC apps. Defines the **hooks contract** (what every commit must be gated on) and points Claude at the right flavor skill per stack
- **A multi-language `.gitignore`** baseline

No `package.json`, no `pyproject.toml`, no `.pre-commit-config.yaml`. The harness is *the rules*; Claude picks the *tooling* at bootstrap time to match your stack.

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

| Gate | Purpose |
|---|---|
| Secret scanning | Catches API keys, tokens, credentials in staged files |
| Dependency vulnerability scan | Blocks commits that introduce known-vulnerable deps |
| File hygiene | Trailing whitespace, JSON/YAML/TOML syntax, large files, merge markers |
| **Pattern audit** | Refuses to commit until Claude has audited the staged diff for duplicated logic and unnecessary fallbacks |
| Lint + complexity gates | Language-specific: file size, function complexity, nesting depth |

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
2. Get an Anthropic API key at [console.anthropic.com](https://console.anthropic.com/settings/keys). Add it as a repo secret named `ANTHROPIC_API_KEY` at `Settings → Secrets and variables → Actions`. *(Pro/Max subscribers can use OAuth instead — see the commented section in `.github/workflows/claude.yml`.)*
3. Push `main`. Claude is now triggerable.

Billed as GitHub Actions minutes + Anthropic API tokens (or subscription quota if using OAuth).

## Prerequisites

- `git`
- Claude Code (for the `check-patterns` skill and bootstrapping)

Everything else — the pre-commit framework, language tooling, hook implementations — is installed by Claude at bootstrap time based on your stack choice.
