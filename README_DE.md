[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/zone1987/ddev-playwright/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/zone1987/ddev-playwright/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/zone1987/ddev-playwright)](https://github.com/zone1987/ddev-playwright/commits)
[![release](https://img.shields.io/github/v/release/zone1987/ddev-playwright)](https://github.com/zone1987/ddev-playwright/releases/latest)

# DDEV Playwright <!-- omit in toc -->

> 🇬🇧 This README is also available in English: [`README.md`](README.md).

* [Was ist DDEV Playwright?](#was-ist-ddev-playwright)
* [Installation](#installation)
* [Playwright-Version pinnen](#playwright-version-pinnen)
* [Benutzung](#benutzung)
  * [UI-Modus & Reports](#ui-modus--reports)
* [Playwright im Projekt einrichten](#playwright-im-projekt-einrichten)
  * [Shopware](#shopware)
  * [Ergebnis-Ordner ignorieren](#ergebnis-ordner-ignorieren)
* [Wie es funktioniert](#wie-es-funktioniert)
* [Entfernen](#entfernen)
* [Ressourcen](#ressourcen)
* [Credits](#credits)

## Was ist DDEV Playwright?

Ein minimales, CMS-unabhängiges [Playwright](https://playwright.dev/)-Add-on für
[DDEV](https://ddev.com/). Es stellt dir einen **nackten, isolierten Playwright-Container** zur
Verfügung — mehr nicht. Playwright installierst und konfigurierst du selbst in deinem Projekt, genau
wie in jedem Node-Projekt, und führst dessen CLI über den Container aus.

Das ist bewusst schlank gehalten: keine Auto-Discovery, keine generierten Configs, keine
projektspezifischen Konfigurationsdateien außer dem Versions-Pin. Der Container nutzt das offizielle
Image `mcr.microsoft.com/playwright` mit allen Browsern vorinstalliert, sodass nichts Schweres auf
deinem Host landet.

Kernfunktionen:

* **Nackter Container** — das offizielle Playwright-Image mit vorinstallierten Browsern; das Setup
  gehört dir.
* **Version pinnen** — eine einzige Einstellung steuert den Image-Tag.
* **Nativer UI-Modus** — Playwrights UI-Modus in DDEV ausführen, erreichbar im Browser.
* **CLI-Durchreichung** — `ddev playwright <args>` wird direkt an die Playwright-CLI weitergeleitet.
* **Plattformübergreifend** — macOS, Linux und Windows (WSL2).

## Installation

```bash
ddev add-on get zone1987/ddev-playwright
ddev restart
```

Committe anschließend das `.ddev`-Verzeichnis in deine Versionsverwaltung. Das Add-on fügt nur zwei
Dateien hinzu: `docker-compose.playwright.yaml` (den Container) und `commands/host/playwright` (den
CLI-Wrapper).

## Playwright-Version pinnen

Die Playwright-Version ist der Docker-Image-Tag. Der Standard steckt in
`docker-compose.playwright.yaml`; überschreibe ihn projektweise, indem du `PLAYWRIGHT_IMAGE_TAG` in
`.ddev/.env` setzt:

```bash
ddev dotenv set .ddev/.env --playwright-image-tag v1.57.0-noble
ddev restart
```

> [!IMPORTANT]
> **Die `@playwright/test`-Version in deiner `package.json` muss zu diesem Image-Tag passen.** Die
> Browser sind im Image vorinstalliert (unter `/ms-playwright`), und der Container zeigt Playwright
> über `PLAYWRIGHT_BROWSERS_PATH` darauf. Stimmen die Versionen nicht überein, sucht Playwright nach
> einem Browser-Build, der nicht im Image liegt, und meldet **„keine Browser installiert"** /
> `Executable doesn't exist` — z. B. beim ersten Start des UI-Modus. **Behebe das nicht** mit
> `ddev playwright install`: Das lädt die Browser nur nicht-persistent nach, sie sind nach dem
> nächsten `ddev restart` wieder weg. Pinne stattdessen dieselbe Version auf beiden Seiten — z. B.
> Image-Tag `v1.56.1-noble` ↔ `@playwright/test` `1.56.1` — dann passen Browser und Runner zusammen
> und es ist nie ein Installationsschritt nötig.

## Benutzung

Führe den Befehl **aus dem Verzeichnis aus, in dem du Playwright installiert hast** (Projekt-Root
oder ein Unterordner — siehe unten). Er mappt dieses Verzeichnis in den Container und führt dort
`npx playwright` aus.

| Befehl | Beschreibung |
| ------ | ------------ |
| `ddev playwright test` | Deine Tests ausführen |
| `ddev playwright test <pfad>` | Bestimmte Tests ausführen |
| `ddev playwright --ui` | Playwrights nativen UI-Modus im Browser öffnen |
| `ddev playwright test --headed --grep @smoke` | Beliebige Playwright-CLI-Argumente werden durchgereicht |
| `ddev playwright codegen https://myproject.ddev.site` | Jedes Playwright-CLI-Unterkommando funktioniert |
| `ddev playwright --version` | Die Playwright-Version ausgeben |
| `ddev logs -s playwright` | Die Logs des Playwright-Containers prüfen |

### UI-Modus & Reports

| Zweck | URL |
| ----- | --- |
| UI-Modus (`ddev playwright --ui`) | `https://<projekt>.ddev.site:8078` |
| HTML-Report (`ddev playwright show-report` per Durchreichung) | `https://<projekt>.ddev.site:9324` |

## Playwright im Projekt einrichten

Da das Add-on nur den Container bereitstellt, installierst du Playwright selbst. Tu das in dem
Verzeichnis, das das Test-Setup besitzen soll (Projekt-Root oder ein Unterordner wie `shopware/`):

```bash
cd shopware   # dort, wo deine package.json liegen soll
ddev exec -s playwright npm init -y
ddev exec -s playwright npm install -D @playwright/test
```

Lege dann eine `playwright.config.js` (oder `.ts`) neben diese `package.json`. Führe die Tests aus
demselben Verzeichnis aus: `cd shopware && ddev playwright test`.

### Shopware

Shopware-Projekte haben ein eigenes Schritt-für-Schritt-Setup — eine Admin-Integration anlegen, die
Acceptance-Test-Suite einbinden und Tests in jedem Plugin/jeder App ablegen. Siehe den eigenen
Leitfaden:

**➡️ [Shopware-Leitfaden](docs/SHOPWARE_DE.md)** ([in English](docs/SHOPWARE.md))

Eine fertige [`playwright.config.js`](examples/shopware/playwright.config.js), eine
[`package.json`](examples/shopware/package.json) und [Beispieltests](examples/shopware/tests) findest
du unter `examples/shopware/`.

### Ergebnis-Ordner ignorieren

Playwright schreibt Traces, Screenshots und Videos in den `outputDir`. Nimm ihn in die `.gitignore`
des Plugins auf, damit Ergebnisse nie committet werden:

```gitignore
# .gitignore im Plugin
/playwright-results/
```

## Wie es funktioniert

* **`docker-compose.playwright.yaml`** — fügt einen isolierten `playwright`-Service auf Basis von
  `mcr.microsoft.com/playwright` hinzu. Browser sind im Image vorinstalliert. Der Image-Tag ist
  `mcr.microsoft.com/playwright:${PLAYWRIGHT_IMAGE_TAG:-<default>}`, sodass du die Version über
  `.ddev/.env` pinnst. Der Projekt-Root wird unter `/var/www/html` gemountet; die Ports für UI (8077)
  und HTML-Report (9323) werden über den DDEV-Router bereitgestellt.
* **`commands/host/playwright`** — der `ddev playwright`-Wrapper. Er mappt dein aktuelles Verzeichnis
  in den Container und führt dort `npx --no-install playwright <args>` aus, sodass Config und
  `node_modules` von dort aufgelöst werden, wo du Playwright installiert hast.

## Entfernen

```bash
ddev add-on remove playwright
```

Verwende den Add-on-**Namen** (`playwright`), nicht den Repository-Slug.

## Ressourcen

* **Du nutzt Shopware?** Siehe den [Shopware-Leitfaden](docs/SHOPWARE_DE.md)
  ([in English](docs/SHOPWARE.md)).
* **Entwickeln oder beitragen?** Siehe [`docs/README_DEV.md`](docs/README_DEV.md).
* [Playwright-Dokumentation](https://playwright.dev/docs/intro)
* [Shopware Acceptance Test Suite](https://developer.shopware.com/docs/guides/development/testing/e2e-playwright/install-configure.html)
* [DDEV-Dokumentation zu Add-ons](https://docs.ddev.com/en/stable/users/extend/additional-services/)

## Credits

**Beigetragen und gepflegt von [@zone1987](https://github.com/zone1987)**
