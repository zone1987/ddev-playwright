[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/zone1987/ddev-playwright/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/zone1987/ddev-playwright/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/zone1987/ddev-playwright)](https://github.com/zone1987/ddev-playwright/commits)
[![release](https://img.shields.io/github/v/release/zone1987/ddev-playwright)](https://github.com/zone1987/ddev-playwright/releases/latest)

# DDEV Playwright

## Overview

This add-on integrates Playwright into your [DDEV](https://ddev.com/) project.

## Installation

```bash
ddev add-on get zone1987/ddev-playwright
ddev restart
```

After installation, make sure to commit the `.ddev` directory to version control.

## Usage

| Command | Description |
| ------- | ----------- |
| `ddev describe` | View service status and used ports for Playwright |
| `ddev logs -s playwright` | Check Playwright logs |

## Advanced Customization

To change the Docker image:

```bash
ddev dotenv set .ddev/.env.playwright --playwright-docker-image="ddev/ddev-utilities:latest"
ddev add-on get zone1987/ddev-playwright
ddev restart
```

Make sure to commit the `.ddev/.env.playwright` file to version control.

All customization options (use with caution):

| Variable | Flag | Default |
| -------- | ---- | ------- |
| `PLAYWRIGHT_DOCKER_IMAGE` | `--playwright-docker-image` | `ddev/ddev-utilities:latest` |

## Credits

**Contributed and maintained by [@zone1987](https://github.com/zone1987)**
