#!/usr/bin/env bash
# run_scan.sh
# Runs snyk test before a git commit and saves the report.

set -euo pipefail

REPORT_DIR="${TABNINE_PROJECT_DIR}/reports"
REPORT_PATH="${REPORT_DIR}/snyk-report.json"

mkdir -p "$REPORT_DIR"

if ! command -v snyk &>/dev/null; then
  echo "snyk not found — run setup_snyk.cjs to install"
  exit 1
fi

snyk test --file="${TABNINE_PROJECT_DIR}/pom.xml" 
  --severity-threshold=high 
  --json-file-output="$REPORT_PATH" 2>&1

if [ $? -eq 0 ]; then
  echo "snyk: clean — no high/critical vulnerabilities found"
else
  echo "snyk: vulnerabilities detected — check reports/snyk-report.json"
fi
