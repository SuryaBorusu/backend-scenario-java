#!/usr/bin/env bash
# run_scan.sh
# Runs gitleaks on the project working tree and saves the report.

set -euo pipefail

REPORT_DIR="${TABNINE_PROJECT_DIR}/reports"
REPORT_PATH="${REPORT_DIR}/gitleaks-report.json"

mkdir -p "$REPORT_DIR"

if ! command -v gitleaks &>/dev/null; then
  echo "gitleaks not found — run setup_gitleaks.cjs to install"
  exit 1
fi

gitleaks detect 
  --source "$TABNINE_PROJECT_DIR" 
  --no-git 
  --report-format json 
  --report-path "$REPORT_PATH" 2>&1

if [ $? -eq 0 ]; then
  echo "gitleaks: clean"
else
  echo "gitleaks: secrets detected — check reports/gitleaks-report.json"
fi
