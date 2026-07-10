[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/zone1987/ddev-playwright/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/zone1987/ddev-playwright/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/zone1987/ddev-playwright)](https://github.com/zone1987/ddev-playwright/commits)
[![release](https://img.shields.io/github/v/release/zone1987/ddev-playwright)](https://github.com/zone1987/ddev-playwright/releases/latest)

# DDEV Playwright <!-- omit in toc -->

> 🇩🇪 Diese README gibt es auch auf Deutsch: [`README_DE.md`](README_DE.md).

* [What is DDEV Playwright?](#what-is-ddev-playwright)
* [Installation](#installation)
* [Pinning the Playwright version](#pinning-the-playwright-version)
* [Usage](#usage)
  * [UI mode & reports](#ui-mode--reports)
* [Setting up Playwright in your project](#setting-up-playwright-in-your-project)
  * [Shopware](#shopware)
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

> [!IMPORTANT]
> **The `@playwright/test` version in your `package.json` must match this image tag.** The browsers
> ship preinstalled in the image (under `/ms-playwright`), and the container points Playwright at
> them via `PLAYWRIGHT_BROWSERS_PATH`. If the versions differ, Playwright looks for a browser build
> that isn't in the image and reports **"browsers not installed"** / `Executable doesn't exist` —
> for example in UI mode on first launch. Do **not** fix this by running `ddev playwright install`:
> that downloads the browsers non-persistently, so they're gone again after the next `ddev restart`.
> Instead, pin the same version on both sides — e.g. image tag `v1.56.1-noble` ↔ `@playwright/test`
> `1.56.1` — so the browsers and the runner agree and no install step is ever needed.

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

Shopware projects have their own step-by-step setup — creating an admin integration, wiring up the
acceptance test suite, and placing tests inside each plugin/app. See the dedicated guide:

**➡️ [Shopware guide](docs/SHOPWARE.md)** ([auf Deutsch](docs/SHOPWARE_DE.md))

A ready-to-use [`playwright.config.js`](examples/shopware/playwright.config.js),
[`package.json`](examples/shopware/package.json) and [example tests](examples/shopware/tests) are
provided under `examples/shopware/`.

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

* **Using Shopware?** See the [Shopware guide](docs/SHOPWARE.md) ([auf Deutsch](docs/SHOPWARE_DE.md)).
* **Developing or contributing?** See [`docs/README_DEV.md`](docs/README_DEV.md).
* [Playwright documentation](https://playwright.dev/docs/intro)
* [Shopware acceptance test suite](https://developer.shopware.com/docs/guides/development/testing/e2e-playwright/install-configure.html)
* [DDEV documentation for add-ons](https://docs.ddev.com/en/stable/users/extend/additional-services/)

## Credits

**Contributed and maintained by [@zone1987](https://github.com/zone1987)**
