# DDEV Playwright — Developer Guide

This document is for **maintainers and contributors** of the `ddev-playwright` add-on. If you just
want to *use* the add-on, see [`README.md`](README.md) instead.

* [Repository layout](#repository-layout)
* [How it fits together](#how-it-fits-together)
* [Local installation](#local-installation)
* [Local testing](#local-testing)
* [Design notes](#design-notes)
* [Contributing](#contributing)
* [Releases](#releases)

## Repository layout

The add-on is deliberately minimal — it ships a bare Playwright container and a CLI wrapper, nothing
more. On install two files land directly in `.ddev/`: `docker-compose.playwright.yaml` and
`commands/host/playwright`. The compose file MUST stay at the `.ddev/` root — DDEV only loads
`docker-compose.*.yaml` from there, not from subfolders.

| Path | Purpose |
| --- | --- |
| `install.yaml` | Add-on manifest: the two files DDEV installs, plus a post-install hint. |
| `docker-compose.playwright.yaml` | The isolated `playwright` service: official image (browsers preinstalled), version via `${PLAYWRIGHT_IMAGE_TAG}`, project root mounted at `/var/www/html`, UI (8077) + report (9323) ports exposed through the DDEV router. |
| `commands/host/playwright` | The `ddev playwright` wrapper: maps the host CWD into the container and runs `npx --no-install playwright <args>`; `--ui` switches to UI mode. |
| `tests/test.bats` | Integration tests (install the add-on into a real DDEV project). |
| `.github/workflows/tests.yml` | Runs the bats suite on push/PR against DDEV stable + HEAD. |
| `.github/workflows/release.yml` | On a `v*` tag: runs the full suite, then publishes the release only if green. |

## How it fits together

* **The version is the image tag.** `docker-compose.playwright.yaml` uses
  `image: mcr.microsoft.com/playwright:${PLAYWRIGHT_IMAGE_TAG:-<default>}`. Docker Compose
  interpolates `${PLAYWRIGHT_IMAGE_TAG}` from `.ddev/.env` at container-render time, so users pin a
  version with `ddev dotenv set .ddev/.env --playwright-image-tag <tag>` + `ddev restart`. No hook,
  no generated file, no resolver.
* **The command runs Playwright in the user's directory.** The wrapper reads the host CWD (via
  `HostWorkingDir: true`), maps it to its in-container path under `/var/www/html`, and runs
  `npx --no-install playwright <args>` there. So the user's `playwright.config` and `node_modules`
  resolve from wherever they installed Playwright (project root or a subfolder). The add-on installs
  and configures nothing itself.

That's the whole design. Everything else — installing `@playwright/test`, writing a
`playwright.config`, loading `.env` files, CMS test suites — is the user's responsibility, exactly
as in a plain Node project.

## Local installation

The fastest feedback loop while developing — install your working copy into a project:

```bash
ddev add-on get /path/to/ddev-playwright
ddev restart
```

Re-running `ddev add-on get` re-copies the files, so you can iterate without recreating the project.

## Local testing

The add-on is tested with [bats-core](https://bats-core.readthedocs.io/) in
[`tests/test.bats`](tests/test.bats), which installs the add-on into a throwaway DDEV project and
asserts the service comes up and the CLI passthrough works.

**Prerequisites:** [DDEV](https://docs.ddev.com), Docker, and the bats libraries:

```bash
brew install bats-core
brew tap bats-core/bats-core
brew install bats-assert bats-file bats-support
```

**Run the suite** from the add-on root:

```bash
bats ./tests/test.bats
```

## Design notes

* **Bare container only.** The add-on does not install `@playwright/test`, does not scaffold configs,
  and does not discover tests. Keeping it unopinionated avoids the fragile "magic" (env passthrough,
  path resolution, config inheritance) that a one-size-fits-all setup needs.
* **Version = image tag.** Match `PLAYWRIGHT_IMAGE_TAG` to the `@playwright/test` version the user
  installs, or Playwright errors ("Executable doesn't exist"). Browsers ship in the image, so nothing
  is downloaded into the project.
* **CWD mapping.** The wrapper translates the host CWD to `/var/www/html/<rel>` where `<rel>` is the
  path relative to the DDEV approot, so `ddev playwright test` works from any subdirectory that has a
  Playwright install.
* **Windows line endings.** `.gitattributes` pins shell scripts to LF; a CRLF in the shebang would
  break `#!/usr/bin/env bash`.

## Contributing

1. Branch off `main` and make your change.
2. Run the tests locally (`bats ./tests/test.bats --filter-tags '!release'`).
3. Open a pull request. The [`tests`](.github/workflows/tests.yml) workflow runs automatically.

Installed files carry a `#ddev-generated` marker so `ddev add-on get` can update them later. Keep
that marker on any file the add-on installs.

## Releases

Releases are **gated by the full test suite** — see [`release.yml`](.github/workflows/release.yml):

1. Push a version tag: `git tag v1.2.3 && git push origin v1.2.3`.
2. The `test` job runs the bats suite against DDEV **stable and HEAD**.
3. Only if **every** matrix job is green does the `release` job publish the GitHub release.

> [!NOTE]
> The add-on version is independent of the Playwright version. Playwright versions come from the
> official `mcr.microsoft.com/playwright` image via `PLAYWRIGHT_IMAGE_TAG` — there is no image to
> build, so you only cut an add-on release when the add-on's own files change.
