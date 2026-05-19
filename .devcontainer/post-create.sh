#!/usr/bin/env bash
# Runs on every container build (after first create). Stack-agnostic by design:
# only installs npm deps if package.json is present.
#
# Stack-specific post-create steps (e.g. `supabase start`, `uv sync`, etc.)
# are appended below the "stack-specific hooks" anchor by stack skills when
# they're invoked. The anchor block is the contract — stack skills look for
# it, append between the markers, and don't touch anything else.
set -euo pipefail

cyan='\033[0;36m'; green='\033[0;32m'; reset='\033[0m'

if [ -f package.json ]; then
  # Use `npm install`, not `npm ci`. `npm ci` is reproducible but too strict
  # for this context: when devs run `npm install` on their host (different
  # arch — typically macOS arm64) and then rebuild the Linux dev container,
  # the lockfile's platform-specific optionalDeps (e.g. @emnapi/* for @swc/core)
  # drift and `npm ci` refuses with "Missing X from lock file." `npm install`
  # is lenient — it updates the lockfile in place rather than failing. Use
  # `npm ci` in your prod CI pipeline where the lockfile is the source of
  # truth, not here.
  echo -e "${cyan}→ Installing npm dependencies...${reset}"
  npm install
fi

# === Universal harness tools ===
# Installed in every CVC app dev container regardless of stack.

# git-ai: tracks AI-generated code attribution (which agent + prompt produced
# each line). Survives rebases/merges via Git Notes. Local-first by default
# — no telemetry leaves the container without explicit team-cloud config.
# Docs: https://usegitai.com
GIT_AI_VERSION=1.4.11
if ! command -v git-ai >/dev/null 2>&1; then
  arch=$(uname -m)
  case "$arch" in
    x86_64)  ga_asset="git-ai-linux-x64" ;;
    aarch64) ga_asset="git-ai-linux-arm64" ;;
    *) echo "  WARN: unknown arch '$arch' — install git-ai manually" >&2; ga_asset="" ;;
  esac
  if [ -n "$ga_asset" ]; then
    echo -e "${cyan}→ Installing git-ai v${GIT_AI_VERSION} (AI-code attribution)...${reset}"
    sudo curl -fsSL -o /usr/local/bin/git-ai \
      "https://github.com/git-ai-project/git-ai/releases/download/v${GIT_AI_VERSION}/${ga_asset}"
    sudo chmod +x /usr/local/bin/git-ai
    # Preserve attribution notes across rebases / merges / cherry-picks.
    if [ -d .git ]; then
      git config --local notes.rewrite.amend true
      git config --local notes.rewriteRef 'refs/notes/git-ai/*' || true
    fi
  fi
fi
# === End universal harness tools ===

# === BEGIN flavor-tooling hooks (appended by setup-*-flavor skills) ===
# Language-flavor tooling that isn't installable via the project's package
# manager (e.g. Go binaries needed by lint-staged hooks). Appended here so
# every container rebuild ensures the tools are present and on PATH.
# === END flavor-tooling hooks ===

# === BEGIN stack-specific hooks (appended by setup-*-stack skills) ===
# Stack-level boot-up (e.g. `supabase start`, `uv sync`, framework-specific
# startup). Runs after flavor tooling is in place.
# === END stack-specific hooks ===

cat <<EOF

${green}═══════════════════════════════════════════════════════════════${reset}
${green}✓ Dev container ready${reset}

If you haven't bootstrapped a stack yet, open Claude Code and ask, e.g.:
  ${cyan}"set me up for a React + Supabase starter app"${reset}
  ${cyan}"set me up for a FastAPI + Postgres backend"${reset}
  ${cyan}"set me up for an MCP server in Python"${reset}

Claude reads ${cyan}CLAUDE.md${reset}, invokes the right flavor + stack
skills, modifies this devcontainer + post-create as needed, then guides
you on rebuilding.
${green}═══════════════════════════════════════════════════════════════${reset}

EOF
