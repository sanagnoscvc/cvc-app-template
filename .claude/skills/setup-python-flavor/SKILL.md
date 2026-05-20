---
name: setup-python-flavor
description: |
  **Python Flavor**: `pre-commit` framework + ruff (lint + complexity + format)
  + mypy + pytest+coverage + gitleaks + osv-scanner. Wires the
  `check-patterns` gate as a `local` hook. Defaults to `uv` (Python 3.12).
  Trigger: "set up Python", "FastAPI", "FastMCP server", any Python stack.
---

# Python Flavor

Run **after** a framework scaffold (FastAPI, FastMCP, etc.) so `pyproject.toml` exists. Canonical configs live in `assets/`; this skill copies them.

The shipped `.pre-commit-config.yaml` enforces the same 5-gate contract as the TS flavor: hygiene (pre-commit-hooks) → secrets (gitleaks) → dep vulns (osv-scanner) → ruff lint+format + mypy → **per-file coverage** (`scripts/check-staged-coverage.py` reading pytest-cov's JSON output) → patterns audit. The coverage gate enforces ≥75% per-file overall and ≥60% branch coverage when `--cov-branch` is enabled. Escape hatch: `STAGED_COVERAGE_SKIP=1 git commit ...`.

> **Status: not yet validated end-to-end.** The TS flavor has seen four test runs and is stable; this Python equivalent is still theoretical. Surface unexpected friction.

## Steps

### 1. Pre-flight

```bash
[ -f CLAUDE.md ] && [ -f scripts/check-patterns.sh ] || {
  echo "Not in a cvc-app-template clone."; exit 1;
}
command -v uv >/dev/null 2>&1 || {
  echo "Install uv first: brew install uv  OR  curl -LsSf https://astral.sh/uv/install.sh | sh"
  exit 1;
}
```

### 2. Initialize project (if needed)

```bash
[ -f pyproject.toml ] || uv init --python 3.12 .
```

### 3. Install dev deps

```bash
uv add --dev pre-commit ruff mypy pytest pytest-cov pip-audit
```

### 4. Copy canonical configs

```bash
cp .claude/skills/setup-python-flavor/assets/.pre-commit-config.yaml ./.pre-commit-config.yaml
cp .claude/skills/setup-python-flavor/assets/.osv-scanner.toml ./.osv-scanner.toml
```

### 5. Append ruff/mypy/pytest config to `pyproject.toml`

```bash
cat .claude/skills/setup-python-flavor/assets/ruff-config.toml >> pyproject.toml
```

(Skip the comment header line by reviewing the file first.)

### 6. Activate `pre-commit` hooks

```bash
uv run pre-commit install
```

### 7. Verify

```bash
uv run ruff check . && uv run ruff format --check . && uv run pytest
```

### 8. Hand-off message

> "Python flavor wired. Try a commit — pre-commit runs ruff + mypy + gitleaks + osv-scanner, then the patterns gate refuses until `/check-patterns` stamps."

## Constraints

- Don't soften the complexity gates (`max-complexity = 12`, `max-statements = 25`).
- Don't replace `bash scripts/check-patterns.sh` with anything else in `.pre-commit-config.yaml`.
- Don't add `pip` + `poetry` alongside `uv`. Pick one.
