// #ddev-generated
//
// Global Playwright configuration for the DDEV Playwright add-on.
//
// It reads the resolved manifest (.ddev/playwright/paths.json), scans the
// configured searchPaths, and builds one Playwright project per discovered
// instance that does NOT ship its own playwright.config ("bundled" instances).
// Instances that DO have their own config are run separately by the
// `ddev playwright` command (via `--config`), so their settings — including
// browsers/projects — apply verbatim. This file therefore never tries to import
// another config (which is unreliable for ESM/TS configs at load time).
//
// Robustness contract: this module MUST NOT throw at import time. Missing files,
// missing/nonexistent searchPaths and zero instances all resolve to a safe, empty
// projects list — a run then simply finds no tests and exits cleanly.
//
// Edit freely; remove the "#ddev-generated" line to protect it from add-on updates.

import { defineConfig, devices } from '@playwright/test';
import { readFileSync, existsSync, statSync, readdirSync } from 'node:fs';
import path from 'node:path';

const ROOT = '/var/www/html';
const MANIFEST_PATH = '/mnt/ddev_config/playwright/paths.json';

type Manifest = {
  searchPaths: string[];
  instanceConfig: string;
  testDirectory: string;
  baseURL: string;
};

const DEFAULTS: Manifest = {
  // Empty by default — searchPaths are opted into via .ddev/playwright/playwright.yaml.
  searchPaths: [],
  instanceConfig: 'tests/playwright.config.ts',
  testDirectory: 'tests/e2e',
  baseURL: 'http://web',
};

function loadManifest(): Manifest {
  try {
    const raw = JSON.parse(readFileSync(MANIFEST_PATH, 'utf8'));
    return {
      searchPaths: Array.isArray(raw.searchPaths) ? raw.searchPaths : DEFAULTS.searchPaths,
      instanceConfig: raw.instanceConfig ?? DEFAULTS.instanceConfig,
      testDirectory: raw.testDirectory ?? DEFAULTS.testDirectory,
      baseURL: raw.baseURL ?? DEFAULTS.baseURL,
    };
  } catch {
    return { ...DEFAULTS };
  }
}

function isDir(p: string): boolean {
  try {
    return statSync(p).isDirectory();
  } catch {
    return false;
  }
}

function safeReaddir(p: string): string[] {
  try {
    return readdirSync(p);
  } catch {
    return [];
  }
}

function hasSpecFiles(dir: string): boolean {
  // Recursively look for *.spec.ts / *.spec.js. Any read error => false.
  const stack = [dir];
  while (stack.length) {
    const current = stack.pop() as string;
    for (const entry of safeReaddir(current)) {
      const full = path.join(current, entry);
      if (isDir(full)) {
        stack.push(full);
      } else if (/\.spec\.(ts|js|mts|cts|mjs|cjs)$/.test(entry)) {
        return true;
      }
    }
  }
  return false;
}

// An instance "owns" a config if any of these exist in its directory.
function hasOwnConfig(instDir: string, m: Manifest): boolean {
  const candidates = [
    path.join(instDir, m.instanceConfig),
    path.join(instDir, 'playwright.config.ts'),
    path.join(instDir, 'playwright.config.js'),
    path.join(instDir, 'playwright.config.mjs'),
  ];
  return candidates.some((c) => {
    try {
      return existsSync(c);
    } catch {
      return false;
    }
  });
}

type Instance = { name: string; testDir: string };

// Only BUNDLED instances (no own config) are managed here. Instances with their
// own config are handled separately by the command.
function discoverBundledInstances(m: Manifest): Instance[] {
  const found: Instance[] = [];
  for (const sp of m.searchPaths) {
    const abs = path.join(ROOT, sp);
    if (!isDir(abs)) continue; // nonexistent searchPath → skip, never an error
    for (const entry of safeReaddir(abs)) {
      const instDir = path.join(abs, entry);
      if (!isDir(instDir)) continue;
      const testDir = path.join(instDir, m.testDirectory);
      if (!(isDir(testDir) && hasSpecFiles(testDir))) continue;
      if (hasOwnConfig(instDir, m)) continue; // runs standalone, not here
      found.push({ name: path.relative(ROOT, instDir), testDir });
    }
  }
  return found;
}

const manifest = loadManifest();
const instances = discoverBundledInstances(manifest);

// baseURL priority: CMS test-suite conventions (APP_URL for Shopware, WP_BASE_URL
// for WordPress — forwarded by the add-on only when that CMS is detected) >
// manifest baseURL > http://web. Keeps the CMS suites working out of the box
// without breaking the CMS-neutral default.
const baseURL =
  process.env.APP_URL || process.env.WP_BASE_URL || manifest.baseURL || 'http://web';

export default defineConfig({
  use: {
    baseURL,
    // Default browser for bundled instances: the Chromium engine (what Google
    // Chrome is built on), via Playwright's Desktop Chrome device profile. It
    // ships in the official image, so no extra download. To use other browsers
    // (Firefox, WebKit=Safari) give the instance its own playwright.config.
    ...devices['Desktop Chrome'],
  },
  // One project per bundled instance. Empty when none are found — a valid config
  // that simply reports "no tests".
  projects: instances.map((inst) => ({ name: inst.name, testDir: inst.testDir })),
});
