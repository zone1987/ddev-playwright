// Example Playwright config for a Shopware project using the ddev-playwright add-on.
//
// Place this next to your package.json in the Shopware root (e.g. shopware/), set
// "type": "module" in that package.json, and install:
//   ddev exec -s playwright npm install -D @playwright/test @shopware-ag/acceptance-test-suite
//
// Put the Shopware integration credentials in shopware/.env.local (git-ignored):
//   SHOPWARE_ACCESS_KEY_ID="..."
//   SHOPWARE_SECRET_ACCESS_KEY="..."
//
// Run it from that directory: `cd shopware && ddev playwright test` (or `--ui`).

import { defineConfig, devices } from '@playwright/test';
import dotenv from 'dotenv';
import { fileURLToPath } from 'node:url';
import { dirname, resolve, join } from 'node:path';
import fs from 'node:fs';

const rootDir = dirname(fileURLToPath(import.meta.url));

// Playwright does not read .env files on its own; load the credentials the
// @shopware-ag/acceptance-test-suite expects from .env.local into process.env.
dotenv.config({ path: resolve(rootDir, '.env.local') });

// VIRTUAL_HOST is provided to the container by DDEV. The Shopware suite builds
// `${APP_URL}api/`, so keep a trailing slash.
const baseURL = 'https://' + process.env.VIRTUAL_HOST.replace(/\/+$/, '') + '/';
process.env.APP_URL = baseURL;

// The acceptance suite resolves its login field labels via translate(), keyed off
// LANG; keep it in sync with use.locale below so both are German (for German
// admin labels + screenshots). Drop both for the default English admin.
process.env.LANG = 'de-DE';

// One Playwright project per custom static plugin that ships e2e tests under
// custom/static-plugins/<Plugin>/tests/e2e.
const pluginsDir = resolve(rootDir, 'custom/static-plugins');
const projects = fs
  .readdirSync(pluginsDir, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => {
    const testDir = join(pluginsDir, entry.name, 'tests', 'e2e');
    if (!fs.existsSync(testDir)) return null;
    return {
      name: entry.name,
      testDir,
      // Keep each plugin's artefacts inside the plugin (add /playwright-results/
      // to that plugin's .gitignore).
      outputDir: join(pluginsDir, entry.name, 'playwright-results'),
    };
  })
  .filter(Boolean);

export default defineConfig({
  projects,
  // Admin screenshot flows are long (many deliberate steps); keep a generous timeout.
  timeout: 180_000,
  use: {
    ...devices['Desktop Chrome'],
    baseURL,
    ignoreHTTPSErrors: true,       // DDEV uses a self-signed cert
    locale: 'de-DE',              // render the Shopware admin in German
    timezoneId: 'Europe/Berlin',
    trace: 'on',
    screenshot: 'on',
    video: 'retain-on-failure',
  },
});
