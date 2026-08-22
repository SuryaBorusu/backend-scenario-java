---
name: snyk-scanner
description: Dependency and vulnerability scanning using the Snyk CLI. Use when the user wants to scan a project for known vulnerabilities in dependencies, check whether Snyk is installed, install Snyk CLI, run a Snyk test, or review a Snyk report as part of a security review or CI/CD workflow.
---

# Snyk Scanner

## Workflow

### 1. Ensure Snyk CLI is available

Always run the setup script first:

```bash
node <skill-dir>/scripts/setup_snyk.cjs
```

- Exit 0 - Snyk CLI is ready.
- Exit 1 - installation failed; surface the error and stop.

The script installs via `npm install -g snyk` (with `sudo` fallback). Requires Node.js/npm on PATH.

### 2. Authenticate (first-time only)

Snyk requires authentication before scanning:

```bash
snyk auth
```

This opens a browser to log in. For CI/headless environments, set `SNYK_TOKEN` as an environment variable instead:

```bash
export SNYK_TOKEN=<your-token>
```

Check auth status: `snyk whoami`

### 3. Run the scan

```bash
# Test dependencies for known vulnerabilities
snyk test --file=pom.xml

# Limit to high severity and above
snyk test --file=pom.xml --severity-threshold=high

# JSON output for programmatic use
snyk test --file=pom.xml --json > snyk-report.json

# SARIF output for GitHub Code Scanning
snyk test --file=pom.xml --sarif > snyk.sarif

# Monitor project on snyk.io for ongoing tracking
snyk monitor --file=pom.xml
```

### 4. Interpret results

- **Exit 0**: no vulnerabilities at/above threshold - report as clean.
- **Exit 1**: vulnerabilities found - surface each finding:
  - `Severity`: critical / high / medium / low
  - `Vulnerability`: CVE or Snyk ID
  - `Package`: affected dependency name and version
  - `Fix`: available upgrade or patch
- **Exit 2**: Snyk error (auth, network, unsupported project) - check `SNYK_TOKEN` and connectivity.

### 5. Remediation guidance

For each finding, advise the user to:

1. **Upgrade** the affected dependency to the fixed version shown.
2. **Check transitive deps** - run `snyk test --all-projects` for transitive vulnerabilities.
3. **Apply a Snyk patch** if no upgrade is available (`snyk protect`).
4. **Ignore intentionally** only if confirmed false positive: `snyk ignore --id=<vuln-id> --reason="<reason>"`.

## Notes

- Never print or commit `SNYK_TOKEN` - always use GitHub Actions secrets or environment variables.
- `snyk-report.json` and `snyk.sarif` may contain sensitive dependency metadata - add them to `.gitignore`.
- For Maven projects, ensure `./mvnw dependency:resolve` has run before scanning so Snyk can resolve the full dependency tree.
- The PR workflow at `.github/workflows/pr-checks.yml` already includes the `snyk-scan` job using `snyk/actions/maven@master`.
