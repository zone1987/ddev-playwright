[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/zone1987/ddev-playwright/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/zone1987/ddev-playwright/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/zone1987/ddev-playwright)](https://github.com/zone1987/ddev-playwright/commits)
[![release](https://img.shields.io/github/v/release/zone1987/ddev-playwright)](https://github.com/zone1987/ddev-playwright/releases/latest)

# DDEV Playwright <!-- omit in toc -->

* [What is DDEV Playwright?](#what-is-ddev-playwright)
* [Installation](#installation)
* [Configuration](#configuration)
  * [Per-project version](#per-project-version)
  * [Search paths & discovery](#search-paths--discovery)
  * [Browsers](#browsers)
  * [Bundled vs. standalone instances](#bundled-vs-standalone-instances)
* [CMS integrations](#cms-integrations)
  * [Shopware](#shopware)
  * [WordPress](#wordpress)
* [Extra npm packages](#extra-npm-packages)
  * [Accessibility testing](#accessibility-testing)
* [Usage](#usage)
  * [UI mode & reports](#ui-mode--reports)
* [How it works](#how-it-works)
* [Robustness](#robustness)
* [Platform support](#platform-support)
* [Removal](#removal)
* [Resources](#resources)
* [Credits](#credits)

## What is DDEV Playwright?

A universal, CMS-agnostic [Playwright](https://playwright.dev/) add-on for [DDEV](https://ddev.com/).
It works with **Shopware, WordPress, TYPO3, Contao** — or any other project. Nothing is
CMS-specific.

Playwright runs in an **isolated container** based on the official `mcr.microsoft.com/playwright`
image. Browsers and `node_modules` live only inside the container, so your repository and host
stay clean — no ~2 GB of browsers per project. The add-on **auto-discovers** Playwright test
instances across configurable folders and lets you **pin the Playwright version per project**.

Key features:

* **Isolated & lightweight** — Playwright, its browsers *and* `node_modules` live only inside the
  container (a named Docker volume). Nothing lands in your repo.
* **Per-project version** — the plugin ships `latest`; pin a specific version per DDEV project.
* **Auto-discovery** — finds every instance under configurable `searchPaths` (any directory with
  `tests/e2e` containing `*.spec.ts`/`*.spec.js`).
* **Layered config** — a global config in `.ddev`, deep-merged per instance, with an optional
  project-root config in between.
* **Optional CMS integrations** — auto-detects Shopware and WordPress and wires up their official
  E2E tooling; a no-op for every other project.
* **Native UI mode** — run Playwright's UI mode inside DDEV, reachable in your browser (no
  XQuartz/VNC).
* **Robust** — no config, no test folders, non-existent `searchPaths`, zero instances: never an
  error.
* **Cross-platform** — macOS, Linux and Windows (WSL2).

## Installation

```bash
ddev add-on get zone1987/ddev-playwright
ddev restart
```

Commit the `.ddev` directory to version control afterwards.

## Configuration

All configuration lives in `.ddev/playwright.yaml`. Every key is optional — missing keys fall back
to the shipped defaults, so a file with only `version` still inherits the default `searchPaths`.

```yaml
version: 1

playwright:
  # Playwright version. Drives BOTH the Docker image tag and @playwright/test.
  # Omit or leave empty to use "latest".
  version: "1.56.1"

  # Folders scanned for Playwright instances (relative to the project root).
  # EMPTY by default — nothing is scanned until you add paths here.
  searchPaths:
    - custom/plugins
    - vendor
    - packages
    - extensions

  # Where a per-instance config lives (relative to an instance directory).
  instanceConfig: tests/playwright.config.ts

  # Where the spec files live (relative to an instance directory).
  testDirectory: tests/e2e

  # How instance configs merge onto the global config ("deep" = recursive).
  mergeStrategy: deep
```

The file carries a `#ddev-generated` marker. As long as you keep it, `ddev add-on get` can update
the file on a later install; remove the marker and DDEV treats it as yours and never overwrites it.

### Per-project version

To pin a different version in a specific project, override just that key:

```yaml
playwright:
  version: "1.38.6"
```

Then `ddev restart`. Each DDEV project has **its own container and its own version** — a version
change in one project never affects another. The `version` value drives both the Docker image tag
(`mcr.microsoft.com/playwright:v<version>-noble`) and the installed `@playwright/test`, so they
always match.

> [!NOTE]
> `searchPaths`, `testDirectory` and discovery are re-read on **every** `ddev playwright`
> invocation, so those changes take effect **without a restart**. Only a **version** change
> requires `ddev restart` (the container image is fixed at build time); the command warns you when
> the running container no longer matches the configured version, but keeps working.

### Search paths & discovery

`searchPaths` is **empty by default** — the add-on scans nothing until you opt in by adding paths
to your `playwright.yaml` (this keeps it CMS-neutral out of the box). Once set, any subdirectory of
a `searchPaths` folder that contains `<testDirectory>` (default `tests/e2e`) with
`*.spec.ts`/`*.spec.js` files becomes a Playwright *project*:

```
custom/plugins/
├── AcmeFoo/
│   └── tests/e2e/example.spec.ts   ← discovered as "custom/plugins/AcmeFoo"
└── AcmeBar/
    └── tests/e2e/                  ← no spec files: ignored
```

Paths that don't exist are silently skipped — never an error. Run `ddev playwright discover` to see
what was found, or `ddev playwright doctor` for a full report. The app under test is reachable
inside the container at `http://web`, the default `baseURL`.

### Bundled vs. standalone instances

Each discovered instance is handled in one of two ways:

* **Bundled** — an instance **without** its own `playwright.config`. It's collected into the global
  `.ddev/playwright/config.ts` (shared `baseURL`, Chromium default) and run together with the other
  bundled instances in a single pass.
* **Standalone** — an instance **with** its own `playwright.config` (at `instanceConfig`, or a
  `playwright.config.*` in the instance dir). It's run separately with that exact config, so its
  `projects`, browsers and options apply verbatim. Extend the global baseline with
  `import base from '/mnt/ddev_config/playwright/config.ts'` and spread `...base`.

`ddev playwright install` scaffolds a minimal standalone config (extending the global one) for any
discovered instance that has none yet — existing files are never overwritten.

### Browsers

The official image ships the **Chromium** engine (what Google Chrome is built on), **Firefox** and
**WebKit** (the **Safari** engine). Browsers are configured the standard Playwright way — through the
`projects` in an instance's own `playwright.config`. An instance that has its own config is run with
exactly that config (its browsers apply verbatim):

```ts
// custom/plugins/AcmeFoo/tests/playwright.config.ts
import { defineConfig, devices } from '@playwright/test';
import base from '/mnt/ddev_config/playwright/config.ts';

export default defineConfig({
  ...base,
  testDir: './e2e',
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox',  use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit',   use: { ...devices['Desktop Safari'] } },   // Safari engine
  ],
});
```

Instances **without** their own config are bundled into the global config and run on **Chromium**
(the Chrome engine) by default. To use Firefox or WebKit for such an instance, give it a
`playwright.config` as above.

> [!NOTE]
> Real Google Chrome (`channel: 'chrome'`) is not bundled in the official image (only the Chromium
> engine is). If you specifically need the branded Chrome binary, add
> `"@playwright/browser-chrome"` or run `playwright install chrome` and set `channel: 'chrome'` in
> your instance config.

## CMS integrations

The add-on core is fully CMS-neutral. On top of that, it can **additionally** wire up the official
E2E tooling for specific CMSes — but only when it detects one. A plain project (or any other CMS)
is never touched by this.

### Shopware

Detected via a `composer.json` requiring `shopware/core` (project root, DDEV docroot, or a common
subfolder). When detected, the add-on installs
[`@shopware-ag/acceptance-test-suite`](https://developer.shopware.com/docs/guides/development/testing/e2e-playwright/install-configure.html)
on `ddev playwright install` and forwards the suite's variables into the container.

Authentication uses a Shopware **integration** (API access key + secret). Set these in your project's
own env files — variable names per the
[Shopware E2E guide](https://developer.shopware.com/docs/guides/development/testing/e2e-playwright/install-configure.html):

```bash
SHOPWARE_ACCESS_KEY_ID="<your-shopware-integration-id>"
SHOPWARE_SECRET_ACCESS_KEY="<your-shopware-integration-secret>"
```

> **One source of truth.** The playwright container reads these directly from your app's
> `.env`, `.env.local` and `.env.test` (loaded in that order — later wins, matching Symfony
> precedence). Keep them in **one** place; there is nothing to duplicate. Put the secret in
> `.env.local` (git-ignored by default) so it never gets committed. The add-on works whether your
> app lives in the project root or a subfolder (e.g. `shopware/`) — it locates the env dir
> automatically. You never edit `.ddev/.env.playwright`; it is generated and carries no credentials.

#### Creating the integration in Shopware

To obtain those two values, create an API integration in the Shopware admin:

1. Open the Administration and go to **Settings → System → Integrations**.
2. Click **Add integration**.
3. Give it a name (e.g. `playwright-e2e`) and, so it can access the data the tests need, assign the
   **Administrator** role (or a role with the required privileges).
4. Save. Shopware shows the **Access key ID** and a **Secret access key** — the secret is displayed
   **only once**, so copy it immediately.
5. Put the Access key ID into `SHOPWARE_ACCESS_KEY_ID` and the secret into
   `SHOPWARE_SECRET_ACCESS_KEY` in your project `.env.local` (recommended, git-ignored) or `.env`,
   then run `ddev restart`.

`APP_URL` (the suite's base URL) defaults to your project's primary DDEV URL (`DDEV_PRIMARY_URL`); a
value you set in `.env`/`.env.local` always wins. Override detection in `playwright.yaml`:

```yaml
playwright:
  shopware: auto        # auto (default) | true (force on) | false (force off)
  shopwareRoot: apps/shop   # explicit path if Shopware lives in an unusual subfolder
```

### WordPress

Detected via WordPress markers (`wp-load.php`, `wp-includes/version.php`) in the project root, DDEV
docroot or a common subfolder, or a DDEV `type: wordpress`. When detected, the add-on installs
[`@wordpress/e2e-test-utils-playwright`](https://developer.wordpress.org/news/2026/05/getting-started-writing-wordpress-e2e-tests-with-playwright/)
on `ddev playwright install` and forwards its variables. Tests run against the **running DDEV site**
— it does not start a separate `wp-env` container.

These are optional in your project `.env` (or `.env.local`, which takes precedence) — variable names
per the
[WordPress E2E guide](https://developer.wordpress.org/news/2026/05/getting-started-writing-wordpress-e2e-tests-with-playwright/):

```bash
WP_BASE_URL="<url-to-your-wordpress>"   # defaults to DDEV_PRIMARY_URL
WP_USERNAME="<admin-user>"              # defaults to "admin"
WP_PASSWORD="<admin-password>"          # defaults to "password"
```

Override detection in `playwright.yaml`:

```yaml
playwright:
  wordpress: auto        # auto (default) | true (force on) | false (force off)
  wordpressRoot: web/wp  # explicit path if WordPress lives in an unusual subfolder
```

Run `ddev playwright doctor` to verify detection, credentials and the installed suite for either CMS.

## Extra npm packages

Add any npm packages your tests need via the `packages` key in `playwright.yaml`. They are installed
into the central Playwright install on `ddev playwright install` — versioned and reproducible for the
whole team:

```yaml
playwright:
  packages:
    - "@axe-core/playwright"
    - "dotenv@^16"
```

For a quick ad-hoc experiment you can also install directly into the container (not persisted across
a volume reset — prefer `packages` for anything permanent):

```bash
ddev exec -s playwright sh -c 'cd /mnt/ddev_config/playwright && npm install -D <package>'
```

### Accessibility testing

[`@axe-core/playwright`](https://playwright.dev/docs/accessibility-testing) is **always installed**,
so accessibility testing works out of the box — no configuration needed. Use it in any spec:

```ts
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test('home page has no automatically detectable a11y issues', async ({ page }) => {
  await page.goto('/');
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
```

## Usage

| Command | Description |
| ------- | ----------- |
| `ddev playwright` | Run all discovered tests (headless) |
| `ddev playwright --ui` | Open Playwright's native UI mode in the browser |
| `ddev playwright install` | Install `@playwright/test` + per-instance deps, scaffold missing configs |
| `ddev playwright discover` | List discovered Playwright instances |
| `ddev playwright doctor` | Diagnose the setup (service, version, config, discovery, Shopware) |
| `ddev playwright show-report` | Serve the last HTML report |
| `ddev playwright cli <args>` | Run any raw Playwright CLI command (`codegen`, `open`, `--version`, …) |
| `ddev playwright --dir <path>` | Target a single instance |
| `ddev playwright test -- <args>` | Pass extra arguments through to Playwright |
| `ddev logs -s playwright` | Check the Playwright container logs |

The full Playwright CLI is available via `ddev playwright cli`, e.g. record a test with the codegen
recorder or inspect the version:

```bash
ddev playwright cli codegen https://myproject.ddev.site
ddev playwright cli --version
```

Everything after `--` is passed straight to `playwright test`:

```bash
ddev playwright test -- --headed --grep "@smoke"
```

### UI mode & reports

| Purpose | URL |
| ------- | --- |
| UI mode (`ddev playwright --ui`) | `https://<project>.ddev.site:8078` |
| HTML report (`ddev playwright show-report`) | `https://<project>.ddev.site:9324` |

## How it works

* **`docker-compose.playwright.yaml`** — adds an isolated `playwright` service based on
  `mcr.microsoft.com/playwright`. Browsers ship preinstalled in the image; `node_modules` lives in
  a named volume (`playwright-node-modules`), so nothing heavy hits your host or repo. The UI (8077)
  and HTML report (9323) ports are exposed through the DDEV router.
* **`playwright.yaml`** — your configuration (see above), at `.ddev/playwright.yaml`.
  `playwright/defaults.yaml` holds the baseline values it is deep-merged onto.
* **`playwright/bin/resolve-config.sh`** — runs on the host (POSIX-only, no Docker needed). It reads
  `.ddev/playwright.yaml`, derives the image tag into `.ddev/.env.playwright`, and writes the
  resolved `.ddev/playwright/paths.json` manifest.
* **`config.playwright.yaml`** — a `pre-start` hook runs the resolver **before** DDEV renders
  docker-compose, so the right image is pulled; a `post-start` hook does a non-fatal version-drift
  check.
* **`playwright/config/config.ts`** — copied to `.ddev/playwright/config.ts` on install. It reads
  the manifest, scans the `searchPaths`, builds one Playwright project per discovered instance, and
  deep-merges the config layers.
* **`commands/host/playwright`** — the `ddev playwright` wrapper. It refreshes the manifest, warns
  on version drift, then runs Playwright inside the service.

## Robustness

The add-on never breaks `ddev start` and never errors on an "empty" project:

* No `.ddev/playwright.yaml` → shipped defaults, `:latest` image, empty `searchPaths`.
* No test directories / zero instances → `ddev playwright` runs with no projects and exits 0.
* `searchPaths` pointing at directories that **don't exist** → those paths are skipped silently.
* Config resolution failure → falls back to the `:latest` image.

## Platform support

Runs on **macOS, Linux and Windows (WSL2)**. All host scripts are POSIX `sh`/`bash` and require no
`yq`/`jq`/Docker on the host for config resolution; shell scripts are pinned to LF line endings via
`.gitattributes` so a Windows checkout doesn't break the shebang.

## Removal

```bash
ddev add-on remove playwright
```

Use the add-on **name** (`playwright`), not the repository slug. This removes the add-on files and
the generated `.env.playwright`, `playwright/config.ts` and `playwright/paths.json`.

## Resources

* **Developing or contributing?** See [`README_DEV.md`](README_DEV.md) for repository layout, local
  testing, and the release process.
* [Playwright documentation](https://playwright.dev/docs/intro)
* [DDEV documentation for add-ons](https://docs.ddev.com/en/stable/users/extend/additional-services/)
* [DDEV Add-on Registry](https://addons.ddev.com/)

## Credits

**Contributed and maintained by [@zone1987](https://github.com/zone1987)**
