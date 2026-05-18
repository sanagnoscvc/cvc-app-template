---
name: setup-python-flavor
description: |
  **Python Flavor Bootstrap**: Wires the CLAUDE.md hooks contract into a Python
  project using the `pre-commit` framework (Python-native idiom). Installs ruff
  for lint + complexity gates, plus pre-commit hooks for gitleaks, osv-scanner,
  and file hygiene. Wires the check-patterns gate as a local hook.
  Trigger: user asks to "set up Python", "bootstrap Python flavor", or names a
  Python stack in a fresh clone (e.g. "set me up for FastAPI + Supabase",
  "FastMCP server").
---

# Python Flavor Bootstrap

You're configuring a clone of `cvc-app-template` for a Python project. This skill encodes the **deterministic** parts: install the right tooling, write the canonical configs, wire `scripts/check-patterns.sh` into the `pre-commit` framework.

After this skill completes, the project will satisfy all five gates in the CLAUDE.md hooks contract (secrets, dep vulns, hygiene, patterns, lint+complexity).

## Decisions to make before starting

Ask the user (or infer from their stack request) if not already clear:

1. **Package manager**: default `uv` (modern, fast, dominant in 2025+). Switch to `pip` + `pip-tools` or `poetry` only if user explicitly asks.
2. **Python version**: default `3.12`. Honor user's preference if stated.

Don't ask about anything else.

## Pre-flight

1. Verify you're in a directory cloned from `cvc-app-template` — check that `scripts/check-patterns.sh` and `CLAUDE.md` exist at the repo root. If not, stop and explain to the user.
2. Check if `pyproject.toml` already exists. If yes, you'll augment it; if no, you'll create it.
3. Check if `.pre-commit-config.yaml` already exists. If yes, append hooks rather than overwriting.

## Procedure

### Step 1 — Initialize project (if needed)

With `uv`:

```bash
uv init --python 3.12 .
```

That creates `pyproject.toml`, `.python-version`, and a minimal `src/` layout.

If `uv` isn't installed, instruct the user:

```bash
# macOS
brew install uv
# Linux/WSL
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Step 2 — Add dev dependencies

```bash
uv add --dev \
  pre-commit \
  ruff \
  mypy \
  pytest \
  pytest-cov \
  pip-audit
```

### Step 3 — Write `.pre-commit-config.yaml`

```yaml
# Pre-commit hooks for this Python project.
# Run `pre-commit install` after pulling fresh, or after adding hooks.

repos:
  # Generic file hygiene
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-merge-conflict
      - id: check-added-large-files
        args: ["--maxkb=1000"]
      - id: check-yaml
      - id: check-json
      - id: check-toml

  # Secret scanning (language-agnostic)
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks

  # Dependency vulnerability scanning
  - repo: https://github.com/google/osv-scanner
    rev: v1.9.2
    hooks:
      - id: osv-scanner
        args: ["-r", "--config=.osv-scanner.toml", "."]

  # Python lint + complexity gates
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.7.4
    hooks:
      - id: ruff
        args: ["--fix", "--exit-non-zero-on-fix"]
      - id: ruff-format

  # Type-checking
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.13.0
    hooks:
      - id: mypy
        additional_dependencies: []

  # Pattern & fallback audit gate
  - repo: local
    hooks:
      - id: check-patterns
        name: Pattern & fallback audit gate
        entry: bash scripts/check-patterns.sh
        language: system
        pass_filenames: false
        always_run: true
```

### Step 4 — Append `[tool.ruff]` config to `pyproject.toml`

Merge into `pyproject.toml` (don't overwrite existing config):

```toml
[tool.ruff]
target-version = "py312"
line-length = 100
extend-exclude = ["build", "dist", ".venv"]

[tool.ruff.lint]
# Enable: pyflakes, pycodestyle, isort, complexity, pep8-naming, bugbear,
# security, sonar-equivalents, line/file/function-size gates
select = [
  "E", "F", "W",     # pycodestyle + pyflakes
  "I",                # isort
  "N",                # pep8-naming
  "B",                # flake8-bugbear
  "C90",              # mccabe (cyclomatic complexity)
  "S",                # flake8-bandit (security)
  "PL",               # pylint conventions (incl. complexity)
  "RUF",              # ruff-specific
]
ignore = [
  "S101",             # use of `assert` (fine in tests)
  "PLR0913",          # too many args — covered by max-args below
]

[tool.ruff.lint.mccabe]
max-complexity = 12

[tool.ruff.lint.pylint]
max-args = 4
max-branches = 12
max-returns = 6
max-statements = 25

[tool.ruff.lint.per-file-ignores]
"tests/**/*.py" = ["S101", "PLR2004"]   # asserts and magic numbers allowed in tests

[tool.mypy]
python_version = "3.12"
strict = true
warn_return_any = true
warn_unused_configs = true

[tool.pytest.ini_options]
addopts = "--cov=src --cov-report=term-missing --cov-fail-under=75"
testpaths = ["tests"]
```

### Step 5 — Write `.osv-scanner.toml`

```toml
# Add vulnerability IDs to ignore here with a written reason.
# [[IgnoredVulns]]
# id = "GHSA-xxxx-xxxx-xxxx"
# reason = "Not applicable: affected codepath is server-only and we use client-only"
```

### Step 6 — Activate `pre-commit`

```bash
uv run pre-commit install
```

(`uv run` ensures the project's venv is used. If not using uv, just `pre-commit install`.)

### Step 7 — Verify

Stage a trivial change and attempt a commit:

```bash
echo "# touched" >> src/__init__.py    # or any staged file
git add .
git commit -m "test: verify pre-commit pipeline"
```

You should see:

1. File hygiene hooks running (trailing whitespace, EOF, etc.)
2. gitleaks scanning staged files
3. osv-scanner scanning the repo
4. ruff linting + formatting staged Python files
5. mypy type-checking
6. The pattern-check gate printing its banner and blocking the commit

That's the expected end-state — the gate refuses because `.patterns-checked` doesn't exist. Tell the user:

> "Python flavor wired. Try a commit — pre-commit will run lint, type-check, security gates, then block on the pattern gate. Run `/check-patterns` to audit and stamp, then retry the commit."

## What you've added

```
pyproject.toml            ← deps + ruff/mypy/pytest config
uv.lock                   ← (auto, if using uv)
.pre-commit-config.yaml   ← hook orchestration
.osv-scanner.toml
.python-version           ← (auto, if uv init)
src/                      ← (auto, if uv init)
```

## What NOT to do

- **Don't soften the complexity gates** (`max-complexity = 12`, `max-statements = 25`, etc.) to make legacy code pass. Refactor instead.
- **Don't replace `bash scripts/check-patterns.sh` with anything else** in `.pre-commit-config.yaml`. The gate script is the canonical artifact.
- **Don't combine this skill with a stack-specific setup** (FastAPI, Supabase, FastMCP, etc.) in one go. Run this first, then handle stack work as a separate operation.
- **Don't add `pip` and `poetry` configs alongside `uv`**. Pick one tool and stick with it for the project.
