#!/usr/bin/env node
/**
 * setup_snyk.cjs
 * Checks if the Snyk CLI is installed; installs the latest release if not.
 * Outputs LLM-friendly status messages and exits 0 on success, 1 on failure.
 */

const { spawnSync } = require("child_process");

function run(cmd, opts = {}) {
  return spawnSync(cmd, { shell: true, encoding: "utf8", ...opts });
}

function isInstalled() {
  return run("snyk --version").status === 0;
}

function getVersion() {
  const r = run("snyk --version");
  return r.status === 0 ? r.stdout.trim() : null;
}

function hasNpm() {
  return run("npm --version").status === 0;
}

function install() {
  if (!hasNpm()) {
    console.error("ERROR: npm is required to install Snyk CLI but was not found on PATH.");
    process.exit(1);
  }

  console.log("Installing Snyk CLI via npm...");
  const r = run("npm install -g snyk --silent");
  if (r.status !== 0) {
    // Try with sudo
    console.log("Retrying with sudo...");
    const sr = run("sudo npm install -g snyk --silent");
    if (sr.status !== 0) {
      console.error(`ERROR: Snyk install failed.
${sr.stderr || r.stderr}`);
      process.exit(1);
    }
  }
}

(async () => {
  if (isInstalled()) {
    console.log(`SUCCESS: Snyk CLI already installed — ${getVersion()}`);
    process.exit(0);
  }

  console.log("Snyk CLI not found. Installing...");
  install();

  if (isInstalled()) {
    console.log(`SUCCESS: Snyk CLI installed — ${getVersion()}`);
    process.exit(0);
  } else {
    console.error("ERROR: Snyk CLI installation appeared to succeed but 'snyk --version' still fails.");
    process.exit(1);
  }
})();
