---
name: secret-scanner
description: Secret and credential scanning using gitleaks. Use when the user wants to scan a repository or file for leaked secrets, API keys, or credentials; check whether gitleaks is installed; install gitleaks; or run a secret scan as part of a security review or CI/CD workflow.
---

# Secret Scanner

## Workflow

### 1. Ensure gitleaks is available

Always run the setup script first. It checks for gitleaks and installs the latest release automatically if missing:

```bash
node <skill-dir>/scripts/setup_gitleaks.cjs
```

- Exit 0 → gitleaks is ready (already installed or just installed).
- Exit 1 → installation failed; surface the error to the user and stop.

The script supports macOS (x64/arm64), Linux (x64/arm64), and Windows (x64). It downloads from the official GitHub releases page — no package manager required.

### 2. Run the scan

After setup succeeds, run gitleaks against the target. Default: scan the current git repository.

```bash
# Scan the full git history of the current repo (most thorough)
gitleaks detect --source . --report-format json --report-path gitleaks-report.json

# Scan only the working-tree files (faster, no history)
gitleaks detect --source . --no-git --report-format json --report-path gitleaks-report.json

# Scan a specific directory
gitleaks detect --source <path> --no-git --report-format json --report-path gitleaks-report.json
```

### 3. Interpret results

- **Exit 0**: no secrets found — report this as clean.
- **Exit 1**: secrets detected — read `gitleaks-report.json` and surface each finding:
  - `Description`: rule that triggered
  - `File` + `Line`: location
  - `Secret`: the matched value (handle carefully — do not echo to logs)
  - `Commit`: commit SHA (if scanning history)
- **Exit 126/127**: gitleaks binary not executable or not on PATH — re-run setup script.

### 4. Remediation guidance

When leaks are found, advise the user to:

1. **Rotate** the exposed secret immediately.
2. **Remove** from history with `git filter-repo` or BFG Repo Cleaner.
3. **Add** the pattern to `.gitleaksignore` only if it is a confirmed false positive.
4. **Force-push** the cleaned history (coordinate with the team).

## Notes

- Never print or log raw secret values into conversation history.
- The JSON report file may contain sensitive data — remind the user to handle it securely and not commit it.
- For CI integration, add `gitleaks detect --source . --report-format sarif --report-path gitleaks.sarif` to the pipeline and upload the SARIF artifact.
