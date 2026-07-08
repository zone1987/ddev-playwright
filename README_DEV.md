# DDEV Playwright — Developer Guide

This document is for **maintainers and contributors** of the `ddev-playwright` add-on. If you just
want to *use* the add-on, see [`README.md`](README.md) instead.

* [Repository layout](#repository-layout)
* [How it fits together](#how-it-fits-together)
* [Local installation](#local-installation)
* [Local testing](#local-testing)
* [Design notes & pitfalls](#design-notes--pitfalls)
* [Contributing](#contributing)
* [Releases](#releases)

## Repository layout

On install these land directly in `.ddev/`: `docker-compose.playwright.yaml`,
`config.playwright.yaml`, `commands/host/playwright`, and the user-editable `playwright.yaml`. The
first two MUST stay at the `.ddev/` root — DDEV only loads compose/config files from there, not from
subfolders. `playwright.yaml` sits there too so it's prominent and easy to edit. Everything else
(defaults, generated config/manifest, helper scripts) lives under `.ddev/playwright/`.

| Path | Purpose |
| --- | --- |
| `install.yaml` | Add-on manifest: which files DDEV installs, plus post-install / removal actions. |
| `docker-compose.playwright.yaml` | The isolated `playwright` service (official image, UI/report ports, `node_modules` volume, Shopware env passthrough). |
| `config.playwright.yaml` | `pre-start` hook (resolve version → `.env.playwright`) + `post-start` version-drift warning. |
| `playwright.yaml` | The user-facing config → `.ddev/playwright.yaml`, shipped with a `#ddev-generated` marker. |
| `playwright/defaults.yaml` | Baseline defaults that `playwright.yaml` is deep-merged onto. |
| `playwright/bin/resolve-config.sh` | Host-side resolver: YAML → `.env.playwright` + `playwright/paths.json`. POSIX-only, Shopware detection. |
| `playwright/bin/discover.mjs` | In-container instance discovery helper (a real file, not inline node, to avoid quote-escaping). |
| `playwright/config/config.ts` | Global config template; copied to `.ddev/playwright/config.ts` on install. Discovery + deep-merge. |
| `commands/host/playwright` | The `ddev playwright` wrapper (test / install / discover / doctor / show-report / `--ui` / `--dir`). |
| `tests/test.bats` | Integration tests (install the add-on into a real DDEV project). |
| `.github/workflows/tests.yml` | Runs the bats suite on push/PR against DDEV stable + HEAD. |
| `.github/workflows/release.yml` | On a `v*` tag: runs the full suite, then publishes the release only if green. |

## How it fits together

The one non-obvious mechanic is **when the Playwright version becomes the Docker image**:

1. `docker-compose.playwright.yaml` interpolates `${PLAYWRIGHT_DOCKER_IMAGE}` from
   `.ddev/.env.playwright` **at container-render time**.
2. That value is written by `resolve-config.sh`, which reads `.ddev/playwright.yaml`.
3. So the resolver must run **before** the container renders. The `pre-start` hook (host-side) is
   exactly that window. Running it in `post-start` would only apply the image on the *next* start.
4. `resolve-config.sh` also runs at **post-install** (for the first restart) and at the start of
   **every `ddev playwright`** call (so `searchPaths`/discovery changes need no restart).

Discovery runs in two places sharing `discover.mjs`. Instances are classified as **bundled** (no own
`playwright.config`) or **standalone** (has one):

* **Bundled** instances are collected by the global `playwright/config.ts` at Playwright load time
  (reads `playwright/paths.json`, scans `searchPaths`, one project each, Chromium default). It does
  **not** import other configs — importing ESM/TS configs synchronously at config-load time is
  unreliable, which is exactly why standalone instances are handled separately.
* **Standalone** instances are run by the `ddev playwright` command one-by-one with
  `playwright test --config=<instance config>`, so their own `projects`/browsers/settings apply
  verbatim. The command orchestrates: bundled group in one run, then each standalone config.

`searchPaths` is **empty by default** — the add-on stays CMS-neutral until the user opts in. CMS
support is an additive layer: detection in
`resolve-config.sh` sets `isShopware` / `isWordpress` in the manifest, which gates the matching
package install and env passthrough — Shopware
([source](https://developer.shopware.com/docs/guides/development/testing/e2e-playwright/install-configure.html))
gets `@shopware-ag/acceptance-test-suite` + `SHOPWARE_*`/`APP_URL`; WordPress
([source](https://developer.wordpress.org/news/2026/05/getting-started-writing-wordpress-e2e-tests-with-playwright/))
gets `@wordpress/e2e-test-utils-playwright` + `WP_*` (tested against the running DDEV site, not
wp-env). A plain project is entirely unaffected.

> [!IMPORTANT]
> `post_install_actions` and `removal_actions` run with the working directory set to the project's
> `.ddev` folder — paths there are relative to `.ddev`, **not** the project root (no `.ddev/` prefix).

## Local installation

The fastest feedback loop while developing — install your working copy into a throwaway project:

```bash
ddev add-on get /path/to/ddev-playwright
ddev restart
ddev playwright discover
```

Re-running `ddev add-on get` re-copies the files and re-runs the post-install actions, so you can
iterate without recreating the project.

## Local testing

The add-on is tested with [bats-core](https://bats-core.readthedocs.io/). The suite in
[`tests/test.bats`](tests/test.bats) installs the add-on into a throwaway DDEV project and asserts
the service, discovery, empty-project robustness and single-instance discovery.

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

Useful variants:

```bash
# Skip the "install from release" test (only test the local copy)
bats ./tests/test.bats --filter-tags '!release'

# Verbose debugging output
bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure
```

You can exercise `resolve-config.sh` in isolation (no DDEV needed) by reproducing the layout under a
fake `.ddev/` — `playwright.yaml` at the `.ddev/` root and `defaults.yaml` in `.ddev/playwright/` —
then running the script directly. It only needs POSIX `sh`/`grep`/`sed`.

## Design notes & pitfalls

* **Version = image + npm.** A single `version` key drives both the image tag
  (`mcr.microsoft.com/playwright:v<version>-noble`) and `@playwright/test@<version>`. They must
  match or Playwright errors ("Executable doesn't exist"); the `post-start` hook warns on drift.
* **No host `yq`/`jq`/Docker for parsing.** `resolve-config.sh` is POSIX-only so it works on
  macOS/Linux/WSL2/Git-Bash. A real `yq` on `PATH` is used for a nicer deep-merge if present, but is
  never required.
* **Windows line endings.** `.gitattributes` pins shell scripts to LF; a CRLF in the shebang would
  break `#!/usr/bin/env bash`. The resolver also strips CR from parsed values defensively.
* **ESM/JSON.** `config.ts` uses `readFileSync`+`JSON.parse` (no import assertions, which are
  Node-version sensitive). Playwright bundles its own TS loader.
* **Module resolution.** `@playwright/test` lives in the `node_modules` volume at
  `/mnt/ddev_config/playwright`, not the project root, so the wrapper runs Playwright with
  `NODE_PATH` + the central `.bin` pointed there (`pw_run`) — otherwise specs can't `import` it.
* **Empty-state exit codes.** `ddev playwright` pre-checks discovery and passes
  `--pass-with-no-tests`, so a project with zero instances exits 0.
* **`node_modules` volume.** Kept in a named Docker volume so it never syncs to the host (fast on
  Mutagen setups) and never lands in the repo.
* **Discovery via a real file.** `discover.mjs` is a shipped file, not an inline `node -e`, so it
  survives passing through `ddev exec … sh -c` without quote-escaping breakage.

## Contributing

1. Branch off `main` and make your change.
2. Run the tests locally (`bats ./tests/test.bats --filter-tags '!release'`).
3. Open a pull request. The [`tests`](.github/workflows/tests.yml) workflow runs automatically.

To install and try out a specific branch or PR without merging:

```bash
# The main branch
ddev add-on get https://github.com/zone1987/ddev-playwright/tarball/main

# A pull request
ddev add-on get https://github.com/zone1987/ddev-playwright/tarball/refs/pull/<PR_NUMBER>/head
```

Installed files carry a `#ddev-generated` marker so `ddev add-on get` can update them later. Keep
that marker on any file the add-on installs — removing it makes DDEV treat the file as user-owned
and stop updating it.

## Releases

Releases are **gated by the full test suite** — see [`release.yml`](.github/workflows/release.yml):

1. Push a version tag: `git tag v1.2.3 && git push origin v1.2.3`.
2. The `test` job runs the **complete** bats suite (including the `@release` test) against DDEV
   **stable and HEAD**.
3. Only if **every** matrix job is green does the `release` job publish the GitHub release
   (auto-generated notes). A red test → no release.

Users then install the latest release with `ddev add-on get zone1987/ddev-playwright`.

> [!NOTE]
> The add-on version is independent of the Playwright version. Playwright versions come from the
> official `mcr.microsoft.com/playwright` image via the `version` key — there is no image to build
> or publish, so you only cut an add-on release when the add-on's own files (commands, hooks,
> config, docs) change.
