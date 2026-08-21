#!/usr/bin/env node
/**
 * setup_gitleaks.cjs
 * Checks if gitleaks is installed; installs the latest release if not.
 * Outputs LLM-friendly status messages and exits 0 on success, 1 on failure.
 */

const { execSync, spawnSync } = require("child_process");
const os = require("os");
const https = require("https");
const fs = require("fs");
const path = require("path");

function run(cmd, opts = {}) {
  return spawnSync(cmd, { shell: true, encoding: "utf8", ...opts });
}

function isInstalled() {
  const r = run("gitleaks version");
  return r.status === 0;
}

function getVersion() {
  const r = run("gitleaks version");
  return r.status === 0 ? r.stdout.trim() : null;
}

function detectPlatform() {
  const p = os.platform();
  const a = os.arch();
  if (p === "darwin") return a === "arm64" ? "darwin_arm64" : "darwin_x64";
  if (p === "linux") return a === "arm64" ? "linux_arm64" : "linux_x64";
  if (p === "win32") return "windows_x64";
  throw new Error(`Unsupported platform: ${p}/${a}`);
}

function fetchLatestVersion() {
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: "api.github.com",
      path: "/repos/gitleaks/gitleaks/releases/latest",
      headers: { "User-Agent": "secret-scanner-skill" },
    };
    https.get(opts, (res) => {
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => {
        try {
          resolve(JSON.parse(body).tag_name.replace(/^v/, ""));
        } catch (e) {
          reject(new Error("Failed to parse GitHub release info"));
        }
      });
    }).on("error", reject);
  });
}

async function installGitleaks() {
  const platform = detectPlatform();
  const version = await fetchLatestVersion();

  // Map our platform keys to gitleaks release asset names
  const assetMap = {
    darwin_arm64: `gitleaks_${version}_darwin_arm64.tar.gz`,
    darwin_x64:   `gitleaks_${version}_darwin_x64.tar.gz`,
    linux_arm64:  `gitleaks_${version}_linux_arm64.tar.gz`,
    linux_x64:    `gitleaks_${version}_linux_x64.tar.gz`,
    windows_x64:  `gitleaks_${version}_windows_x64.zip`,
  };

  const asset = assetMap[platform];
  const downloadUrl = `https://github.com/gitleaks/gitleaks/releases/download/v${version}/${asset}`;
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "gitleaks-"));
  const archivePath = path.join(tmpDir, asset);

  console.log(`Downloading gitleaks v${version} for ${platform}...`);

  // Download
  const dlResult = run(`curl -fsSL "${downloadUrl}" -o "${archivePath}"`);
  if (dlResult.status !== 0) {
    console.error(`ERROR: Download failed.
${dlResult.stderr}`);
    process.exit(1);
  }

  // Extract
  const isWin = platform === "windows_x64";
  const extractCmd = isWin
    ? `unzip -o "${archivePath}" gitleaks.exe -d "${tmpDir}"`
    : `tar -xzf "${archivePath}" -C "${tmpDir}" gitleaks`;
  const extResult = run(extractCmd);
  if (extResult.status !== 0) {
    console.error(`ERROR: Extraction failed.
${extResult.stderr}`);
    process.exit(1);
  }

  // Install to /usr/local/bin (may require sudo on some systems)
  const binary = isWin ? "gitleaks.exe" : "gitleaks";
  const dest = isWin ? path.join("C:\Windows\System32", binary) : `/usr/local/bin/${binary}`;
  const installCmd = isWin
    ? `copy "${path.join(tmpDir, binary)}" "${dest}"`
    : `install -m 755 "${path.join(tmpDir, binary)}" "${dest}"`;

  // Try without sudo first, fall back to sudo
  let instResult = run(installCmd);
  if (instResult.status !== 0) {
    console.log("Retrying install with sudo...");
    instResult = run(`sudo ${installCmd}`);
  }
  if (instResult.status !== 0) {
    console.error(`ERROR: Install failed.
${instResult.stderr}`);
    process.exit(1);
  }

  // Cleanup
  fs.rmSync(tmpDir, { recursive: true, force: true });

  console.log(`SUCCESS: gitleaks v${version} installed to ${dest}`);
}

(async () => {
  if (isInstalled()) {
    console.log(`SUCCESS: gitleaks already installed — ${getVersion()}`);
    process.exit(0);
  }

  console.log("gitleaks not found. Installing...");
  try {
    await installGitleaks();
    process.exit(0);
  } catch (err) {
    console.error(`ERROR: ${err.message}`);
    process.exit(1);
  }
})();
