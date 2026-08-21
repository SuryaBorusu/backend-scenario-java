#!/usr/bin/env bash
# run_scan.sh
# Runs gitleaks on the project working tree and saves the report.
# Exits non-zero if secrets are found (so BeforeTool hooks can block the commit).

set -euo pipefail

PROJECT_ROOT="${TABNINE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
REPORT_DIR="${PROJECT_ROOT}/reports"
REPORT_PATH="${REPORT_DIR}/gitleaks-report.json"

mkdir -p "$REPORT_DIR"

if ! command -v gitleaks &>/dev/null; then
  echo "gitleaks not found — run setup_gitleaks.cjs to install"
  exit 1
fi

# Use git mode so only committed/staged content is scanned (respects .gitignore).
# Falls back to --no-git if not inside a git repo.
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  gitleaks detect --source "$PROJECT_ROOT" --report-format json --report-path "$REPORT_PATH" 2>&1
  LEAK_EXIT=$?
else
  gitleaks detect --source "$PROJECT_ROOT" --no-git --report-format json --report-path "$REPORT_PATH" 2>&1
  LEAK_EXIT=$?
fi

if [ "$LEAK_EXIT" -eq 0 ]; then
  echo "gitleaks: clean — no secrets detected"
  exit 0
else
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  🔴  SECRET DETECTED — COMMIT BLOCKED                       ║"
  echo "║  gitleaks found potential secrets in the staged changes.    ║"
  echo "║  Check: reports/gitleaks-report.json                        ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  exit 1
fi
