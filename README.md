[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/zone1987/ddev-playwright/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/zone1987/ddev-playwright/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/zone1987/ddev-playwright)](https://github.com/zone1987/ddev-playwright/commits)
[![release](https://img.shields.io/github/v/release/zone1987/ddev-playwright)](https://github.com/zone1987/ddev-playwright/releases/latest)

# DDEV Playwright <!-- omit in toc -->

* [What is DDEV Playwright?](#what-is-ddev-playwright)
* [Installation](#installation)
* [Pinning the Playwright version](#pinning-the-playwright-version)
* [Usage](#usage)
  * [UI mode & reports](#ui-mode--reports)
* [Setting up Playwright in your project](#setting-up-playwright-in-your-project)
  * [Shopware](#shopware)
  * [Example: one project per plugin](#example-one-project-per-plugin)
  * [Ignore the results folder](#ignore-the-results-folder)
* [How it works](#how-it-works)
* [Removal](#removal)
* [Resources](#resources)
* [Credits](#credits)

## What is DDEV Playwright?

A minimal, CMS-agnostic [Playwright](https://playwright.dev/) add-on for [DDEV](https://ddev.com/).
It gives you a **bare, isolated Playwright container** — nothing more. You install and configure
Playwright yourself in your project, exactly like in any Node project, and run its CLI through the
container.

This is deliberately unopinionated: no auto-discovery, no generated configs, no per-project config
files beyond the version pin. The container ships the official `mcr.microsoft.com/playwright` image
with all browsers preinstalled, so nothing heavy lands on your host.

Key features:

* **Bare container** — the official Playwright image with browsers preinstalled; you own the setup.
* **Pin the version** — one setting controls the image tag.
* **Native UI mode** — run Playwright's UI mode inside DDEV, reachable in your browser.
* **CLI passthrough** — `ddev playwright <args>` forwards straight to the Playwright CLI.
* **Cross-platform** — macOS, Linux and Windows (WSL2).

## Installation

```bash
ddev add-on get zone1987/ddev-playwright
ddev restart
```

Commit the `.ddev` directory to version control afterwards. The add-on adds just two files:
`docker-compose.playwright.yaml` (the container) and `commands/host/playwright` (the CLI wrapper).

## Pinning the Playwright version

The Playwright version is the Docker image tag. The default is baked into
`docker-compose.playwright.yaml`; override it per project by setting `PLAYWRIGHT_IMAGE_TAG` in
`.ddev/.env`:

```bash
ddev dotenv set .ddev/.env --playwright-image-tag v1.57.0-noble
ddev restart
```

Match this tag to the `@playwright/test` version you install in your project so the browsers and the
runner agree.

## Usage

Run the command **from the directory where you installed Playwright** (your project root or a
subfolder — see below). It maps that directory into the container and runs `npx playwright` there.

| Command | Description |
| ------- | ----------- |
| `ddev playwright test` | Run your tests |
| `ddev playwright test <path>` | Run specific tests |
| `ddev playwright --ui` | Open Playwright's native UI mode in the browser |
| `ddev playwright test --headed --grep @smoke` | Any Playwright CLI args pass straight through |
| `ddev playwright codegen https://myproject.ddev.site` | Any Playwright CLI subcommand works |
| `ddev playwright --version` | Print the Playwright version |
| `ddev logs -s playwright` | Check the Playwright container logs |

### UI mode & reports

| Purpose | URL |
| ------- | --- |
| UI mode (`ddev playwright --ui`) | `https://<project>.ddev.site:8078` |
| HTML report (`ddev playwright show-report` via passthrough) | `https://<project>.ddev.site:9324` |

## Setting up Playwright in your project

Because the add-on is just the container, you install Playwright yourself. Do it in whichever
directory should own the test setup (project root, or a subfolder like `shopware/`):

```bash
cd shopware   # wherever your package.json should live
ddev exec -s playwright npm init -y
ddev exec -s playwright npm install -D @playwright/test
```

Then add a `playwright.config.js` (or `.ts`) next to that `package.json`. Run tests from that same
directory: `cd shopware && ddev playwright test`.

### Shopware

For Shopware, install the official acceptance test suite alongside Playwright:

```bash
ddev exec -s playwright npm install -D @shopware-ag/acceptance-test-suite
```

The suite reads its configuration from **environment variables** (`APP_URL`,
`SHOPWARE_ACCESS_KEY_ID`, `SHOPWARE_SECRET_ACCESS_KEY`). Playwright does not load `.env` files on its
own, so load them in your config. Put the credentials in **`.env.local`** (git-ignored) next to your
`package.json`:

```bash
# shopware/.env.local
SHOPWARE_ACCESS_KEY_ID="<your-shopware-integration-id>"
SHOPWARE_SECRET_ACCESS_KEY="<your-shopware-integration-secret>"
```

Create the integration in the Shopware admin under **Settings → System → Integrations** (assign the
**Administrator** role; the secret is shown only once).

### Example: one project per plugin

A `playwright.config.js` that loads `.env.local`, derives the base URL from the DDEV container, sets
German admin language for the acceptance suite, and registers one Playwright project per plugin under
`custom/static-plugins/*/tests/e2e`:

```js
import { defineConfig, devices } from '@playwright/test';
import dotenv from 'dotenv';
import { fileURLToPath } from 'node:url';
import { dirname, resolve, join } from 'node:path';
import fs from 'node:fs';

const rootDir = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: resolve(rootDir, '.env.local') });

// VIRTUAL_HOST is provided to the container by DDEV. The Shopware suite builds
// `${APP_URL}api/`, so keep a trailing slash.
const baseURL = 'https://' + process.env.VIRTUAL_HOST.replace(/\/+$/, '') + '/';
process.env.APP_URL = baseURL;
// The acceptance suite resolves its login labels via translate(), keyed off LANG;
// keep it in sync with use.locale below so both are German.
process.env.LANG = 'de-DE';

// One project per plugin that has a tests/e2e folder.
const pluginsDir = resolve(rootDir, 'custom/static-plugins');
const projects = fs
  .readdirSync(pluginsDir, { withFileTypes: true })
  .filter((e) => e.isDirectory())
  .map((e) => {
    const testDir = join(pluginsDir, e.name, 'tests', 'e2e');
    if (!fs.existsSync(testDir)) return null;
    return {
      name: e.name,
      testDir,
      // Keep each plugin's artefacts inside the plugin.
      outputDir: join(pluginsDir, e.name, 'playwright-results'),
    };
  })
  .filter(Boolean);

export default defineConfig({
  projects,
  timeout: 180_000,
  use: {
    ...devices['Desktop Chrome'],
    baseURL,
    ignoreHTTPSErrors: true,           // DDEV uses a self-signed cert
    locale: 'de-DE',                   // render the Shopware admin in German
    timezoneId: 'Europe/Berlin',
    trace: 'on',
    screenshot: 'on',
    video: 'retain-on-failure',
  },
});
```

Your `package.json` needs `"type": "module"` for the `import` syntax above (or use `require`).

### Ignore the results folder

Playwright writes traces, screenshots and videos to the `outputDir`. Add it to the plugin's
`.gitignore` so results never get committed:

```gitignore
# .gitignore in the plugin
/playwright-results/
```

## How it works

* **`docker-compose.playwright.yaml`** — adds an isolated `playwright` service based on
  `mcr.microsoft.com/playwright`. Browsers ship preinstalled in the image. The image tag is
  `mcr.microsoft.com/playwright:${PLAYWRIGHT_IMAGE_TAG:-<default>}`, so you pin the version via
  `.ddev/.env`. The project root is mounted at `/var/www/html`; the UI (8077) and HTML report (9323)
  ports are exposed through the DDEV router.
* **`commands/host/playwright`** — the `ddev playwright` wrapper. It maps your current directory into
  the container and runs `npx --no-install playwright <args>` there, so the config and `node_modules`
  resolve from wherever you installed Playwright.

## Removal

```bash
ddev add-on remove playwright
```

Use the add-on **name** (`playwright`), not the repository slug.

## Resources

* **Developing or contributing?** See [`README_DEV.md`](README_DEV.md).
* [Playwright documentation](https://playwright.dev/docs/intro)
* [Shopware acceptance test suite](https://developer.shopware.com/docs/guides/development/testing/e2e-playwright/install-configure.html)
* [DDEV documentation for add-ons](https://docs.ddev.com/en/stable/users/extend/additional-services/)

## Credits

**Contributed and maintained by [@zone1987](https://github.com/zone1987)**
