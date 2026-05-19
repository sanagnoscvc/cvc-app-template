#!/usr/bin/env bash
# Runs on every container build (after first create). Stack-agnostic:
# only does work if the relevant config is present in the workspace.
#
# - If package.json exists → npm install
# - If supabase/config.toml exists → start the local stack + write .env.local
# - Otherwise → quietly print a "ready, ask Claude" message
set -euo pipefail

cyan='\033[0;36m'; green='\033[0;32m'; yellow='\033[0;33m'; reset='\033[0m'

DID_WORK=0

if [ -f package.json ]; then
  echo -e "${cyan}→ package.json detected — installing npm dependencies...${reset}"
  npm install
  DID_WORK=1
fi

if [ -f supabase/config.toml ]; then
  echo -e "${cyan}→ supabase/config.toml detected — starting local Supabase...${reset}"
  echo -e "  ${yellow}(first run pulls ~10 Docker images, takes 2-3 min)${reset}"
  npx supabase start

  echo -e "${cyan}→ Writing .env.local from supabase status...${reset}"
  SB_ENV=$(npx supabase status -o env)
  API_URL=$(printf '%s\n' "$SB_ENV" | awk -F'=' '/^API_URL=/{print $2}' | tr -d '"')
  ANON_KEY=$(printf '%s\n' "$SB_ENV" | awk -F'=' '/^ANON_KEY=/{print $2}' | tr -d '"')

  if [[ -z "$API_URL" || -z "$ANON_KEY" ]]; then
    echo -e "  ${yellow}WARN: couldn't parse API_URL/ANON_KEY from supabase status. Raw output:${reset}" >&2
    printf '%s\n' "$SB_ENV" >&2
    echo -e "  ${yellow}Skipping .env.local generation — generate it manually after fixing.${reset}" >&2
  else
    cat > .env.local <<EOF
VITE_SUPABASE_URL=$API_URL
VITE_SUPABASE_PUBLISHABLE_KEY=$ANON_KEY
EOF
    echo -e "  ${green}.env.local written.${reset}"
  fi
  DID_WORK=1
fi

if [ "$DID_WORK" -eq 0 ]; then
  cat <<EOF

${green}═══════════════════════════════════════════════════════════════${reset}
${green}✓ Dev container ready${reset}

This is a fresh ${cyan}cvc-app-template${reset} clone — no stack bootstrapped yet.

Next: open Claude Code in this directory and ask for what you want, e.g.

  ${cyan}"set me up for a React + Supabase starter app"${reset}
  ${cyan}"set me up for a FastAPI + Postgres backend"${reset}
  ${cyan}"set me up for an MCP server in Python"${reset}

Claude reads ${cyan}CLAUDE.md${reset}, invokes the right flavor skill,
and scaffolds your stack. Re-open the container when prompted and
${cyan}npm run dev${reset} (or whatever your stack uses).
${green}═══════════════════════════════════════════════════════════════${reset}

EOF
else
  cat <<EOF

${green}═══════════════════════════════════════════════════════════════${reset}
${green}✓ Setup complete${reset}

Open a terminal and run your stack's dev command, e.g. ${cyan}npm run dev${reset}.
${green}═══════════════════════════════════════════════════════════════${reset}

EOF
fi
