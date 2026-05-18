# cvc-app-template

A Claude-driven starting point for building internal-tool apps at CVC. Clone this, then ask Claude Code to bootstrap your chosen stack on top.

> **Status:** v0 — universal harness only (no framework or language picked). Language flavors and stack recipes ship in later phases.

## What's in v0

A **stack-agnostic Claude harness**. No pre-installed tooling, no framework assumptions. Cloning gets you:

- **The `check-patterns` Claude skill** — encoded review pass Claude runs before each commit to flag duplicated logic and defensive shims
- **The `check-patterns.sh` gate script** — blocks commits until the audit has run (paired with whatever pre-commit framework Claude wires up for your stack)
- **Flavor bootstrap skills** — `setup-ts-flavor` and `setup-python-flavor` encode the deterministic install + config steps for each language family, so Claude doesn't re-derive them every time
- **`CLAUDE.md`** — Claude's constitution for working in CVC apps. Defines the **hooks contract** (what every commit must be gated on) and points Claude at the right flavor skill per stack
- **A multi-language `.gitignore`** baseline

No `package.json`, no `pyproject.toml`, no `.pre-commit-config.yaml`. The harness is *the rules*; Claude picks the *tooling* at bootstrap time to match your stack.

## Quick start

```bash
# 1. Clone as your project starting point
git clone https://github.com/<org>/cvc-app-template my-new-app
cd my-new-app

# 2. Open with Claude Code
claude
> "set me up for TS + Supabase"     # or whatever stack
```

Claude will then:

1. Read `CLAUDE.md` to understand the hooks contract
2. Pick the language-idiomatic pre-commit framework (husky + lint-staged for TS, the `pre-commit` framework for Python, etc.)
3. Install and configure the gates required by the contract (secrets, dep vulns, hygiene, patterns, lint+complexity)
4. Wire `scripts/check-patterns.sh` into the gate so the `check-patterns` Claude skill is enforced on every commit
5. Scaffold the stack itself

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
├── scripts/
│   └── check-patterns.sh                 ← gate script (blocks commit until stamp exists)
├── .claude/
│   ├── skills/check-patterns/SKILL.md    ← the audit skill
│   └── commands/check-patterns.md        ← /check-patterns slash command
├── CLAUDE.md                             ← Claude's constitution + hooks contract
└── README.md                             ← this file
```

## Prerequisites

- `git`
- Claude Code (for the `check-patterns` skill and bootstrapping)

Everything else — the pre-commit framework, language tooling, hook implementations — is installed by Claude at bootstrap time based on your stack choice.
