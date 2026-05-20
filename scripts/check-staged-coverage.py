#!/usr/bin/env python3
"""Per-file coverage gate for Python (parallel to check-staged-coverage.mjs).

Reads `coverage/coverage-summary.json` produced by `coverage json` (after
pytest-cov). Verifies each staged .py file (excluding tests/) meets per-file
thresholds.

Behavior matches the TS variant:
  - No staged .py files                       -> exit 0 (nothing to check)
  - coverage/coverage-summary.json missing    -> exit 0 with hint (bootstrap-friendly)
  - Staged file present + below threshold     -> BLOCK (exit 1)
  - Staged file absent from report            -> BLOCK (exit 1) (source with no test)

Override: STAGED_COVERAGE_SKIP=1 git commit ...
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

THRESHOLDS = {
    "percent_covered": 75.0,  # coverage.py reports overall %; statements + branches together
}
BRANCH_THRESHOLD = 60.0  # only checked if `branches` key present (requires --cov-branch)


def main() -> int:
    if os.environ.get("STAGED_COVERAGE_SKIP") == "1":
        print("STAGED_COVERAGE_SKIP=1 — coverage gate bypassed (use sparingly).")
        return 0

    staged = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
        capture_output=True, text=True, check=True,
    ).stdout.splitlines()

    py_files = [
        f for f in staged
        if f.endswith(".py")
        and not f.startswith("tests/")
        and "/tests/" not in f
        and not Path(f).name.startswith("test_")
        and not Path(f).name.endswith("_test.py")
    ]

    if not py_files:
        print("Coverage gate: no staged .py — skipped.")
        return 0

    report_path = Path.cwd() / "coverage" / "coverage-summary.json"
    if not report_path.exists():
        print(
            "Coverage gate: coverage/coverage-summary.json not found — skipped.\n"
            "  Run `pytest --cov-report=json:coverage/coverage-summary.json` to enable\n"
            "  the gate. Once a report exists, this gate enforces thresholds on\n"
            "  subsequent commits.",
        )
        return 0

    report = json.loads(report_path.read_text())
    files_section = report.get("files", {})

    failures: list[tuple[str, list[str]]] = []
    not_found: list[str] = []

    for staged_file in py_files:
        entry = files_section.get(staged_file)
        if entry is None:
            not_found.append(staged_file)
            continue

        summary = entry.get("summary", {})
        issues: list[str] = []

        pct = summary.get("percent_covered")
        if pct is not None and pct < THRESHOLDS["percent_covered"]:
            issues.append(f"percent_covered: {pct:.2f}% < {THRESHOLDS['percent_covered']}%")

        branch_pct = summary.get("percent_covered_branches")
        if branch_pct is not None and branch_pct < BRANCH_THRESHOLD:
            issues.append(f"branches: {branch_pct:.2f}% < {BRANCH_THRESHOLD}%")

        if issues:
            failures.append((staged_file, issues))

    if not failures and not not_found:
        print(f"Coverage gate: {len(py_files)} staged file(s) above thresholds. ✓")
        return 0

    print("", file=sys.stderr)
    print("╔══════════════════════════════════════════════════════════════════╗", file=sys.stderr)
    print("║  COVERAGE GATE FAILED                                            ║", file=sys.stderr)
    print("╚══════════════════════════════════════════════════════════════════╝", file=sys.stderr)

    if failures:
        print("\nBelow threshold:", file=sys.stderr)
        for f, issues in failures:
            print(f"  {f}", file=sys.stderr)
            for issue in issues:
                print(f"    {issue}", file=sys.stderr)

    if not_found:
        print("\nNo coverage report entry (file has no associated test):", file=sys.stderr)
        for f in not_found:
            print(f"  {f}", file=sys.stderr)

    print(
        f"\nThresholds: percent_covered >= {THRESHOLDS['percent_covered']}%, "
        f"branches >= {BRANCH_THRESHOLD}% (if --cov-branch)",
        file=sys.stderr,
    )
    print(
        "Fix: add or improve tests, then "
        "`pytest --cov-report=json:coverage/coverage-summary.json` to refresh.",
        file=sys.stderr,
    )
    print("Bypass (use sparingly):  STAGED_COVERAGE_SKIP=1 git commit ...", file=sys.stderr)
    print("", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
