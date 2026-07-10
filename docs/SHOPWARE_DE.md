# Playwright in Shopware-Projekten

> 🇬🇧 This guide is also available in English: [`SHOPWARE.md`](SHOPWARE.md).

Dieser Leitfaden erklärt Schritt für Schritt, wie du das `ddev-playwright`-Add-on in einem
Shopware-Projekt einrichtest und deine ersten End-to-End-Tests schreibst.

> **Wichtig:** Achte darauf, dass **kein anderes Playwright-Add-on** in deinem DDEV-Projekt
> installiert ist. Zwei parallele Playwright-Container/-Wrapper führen zu Konflikten (doppelte
> Ports, konkurrierende `ddev playwright`-Befehle). Prüfe das mit `ddev add-on list` und entferne
> ein eventuell vorhandenes zweites Playwright-Add-on, bevor du fortfährst.

## Inhalt <!-- omit in toc -->

* [1. Add-on installieren](#1-add-on-installieren)
* [2. Integration in Shopware anlegen](#2-integration-in-shopware-anlegen)
* [3. Zugangsdaten in `.env.local` hinterlegen](#3-zugangsdaten-in-envlocal-hinterlegen)
* [4. `package.json` anlegen und Abhängigkeiten installieren](#4-packagejson-anlegen-und-abhängigkeiten-installieren)
  * [Browser sind im Container bereits vorhanden](#browser-sind-im-container-bereits-vorhanden)
* [5. `playwright.config.js` übernehmen](#5-playwrightconfigjs-übernehmen)
* [6. Tests in Plugins und Apps schreiben](#6-tests-in-plugins-und-apps-schreiben)
* [7. Tests ausführen](#7-tests-ausführen)
* [Beispieltests](#beispieltests)

## 1. Add-on installieren

Im Projekt-Root:

```bash
ddev add-on get zone1987/ddev-playwright
ddev restart
```

Committe anschließend das `.ddev`-Verzeichnis in deine Versionsverwaltung.

## 2. Integration in Shopware anlegen

Die Tests melden sich über die **Admin-API** an. Dafür brauchst du eine Integration mit einem
Access-Key und einem Secret.

1. Melde dich in der **Shopware-Administration** an.
2. Öffne **Einstellungen → System → Integrationen** (englisch: *Settings → System → Integrations*).
3. Klicke oben rechts auf **Integration hinzufügen**.
4. Vergib einen Namen, z. B. `Playwright E2E`.
5. **Aktiviere die Option „Administrator"** (Admin-Berechtigung). Ohne Admin-Rechte scheitert der
   Login der Tests, weil die Acceptance-Test-Suite auf die volle Admin-API zugreift.
6. Klicke auf **Integration speichern**.
7. Shopware zeigt dir jetzt **Zugriffs-Schlüssel-ID (Access Key ID)** und **Geheimer
   Zugriffsschlüssel (Secret Access Key)**.

   > ⚠️ **Der geheime Zugriffsschlüssel wird nur ein einziges Mal angezeigt.** Kopiere ihn sofort.
   > Geht er verloren, musst du ihn in der Integration neu generieren.

## 3. Zugangsdaten in `.env.local` hinterlegen

Die Acceptance-Test-Suite liest ihre Zugangsdaten aus **Umgebungsvariablen**. Lege sie in einer
**`.env.local`** neben deiner `package.json` ab (siehe nächster Schritt für den Ort der
`package.json`). Diese Datei ist bei Shopware bereits git-ignoriert und ist die richtige Stelle für
Secrets:

```bash
# .env.local
SHOPWARE_ACCESS_KEY_ID="<deine-access-key-id>"
SHOPWARE_SECRET_ACCESS_KEY="<dein-secret-access-key>"
```

Trage hier die beiden Werte aus Schritt 2 ein.

## 4. `package.json` anlegen und Abhängigkeiten installieren

Lege im **Shopware-Ordner** (dort, wo `custom/` liegt — also der Ordner mit dem Shopware-Root) eine
`package.json` an. Eine fertige Vorlage findest du unter
[`examples/shopware/package.json`](../examples/shopware/package.json):

```json
{
  "name": "shopware-e2e",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "playwright test",
    "test:ui": "playwright test --ui"
  },
  "devDependencies": {
    "@playwright/test": "1.56.1",
    "@shopware-ag/acceptance-test-suite": "^2.0.0",
    "dotenv": "^16.4.5"
  }
}
```

`"type": "module"` ist nötig, weil die Beispiel-Konfiguration `import`-Syntax verwendet.

> **Wichtig — Version muss zum Image passen:** Die `@playwright/test`-Version **muss** exakt dem
> Playwright-Image des Containers entsprechen (`PLAYWRIGHT_IMAGE_TAG` in `.ddev/.env`, Standard
> `v1.56.1-noble`). Deshalb ist oben `1.56.1` fest gepinnt (ohne `^`). Stimmen die Versionen nicht
> überein, sucht Playwright nach einer Browser-Version, die im Image nicht liegt — siehe
> [Browser sind im Container bereits vorhanden](#browser-sind-im-container-bereits-vorhanden).
>
> Willst du eine andere Version nutzen, setze den passenden Image-Tag und pinne dieselbe Version in
> der `package.json`:
>
> ```bash
> ddev dotenv set .ddev/.env --playwright-image-tag v1.57.0-noble
> ddev restart
> ```

Installiere anschließend die Abhängigkeiten über den Playwright-Container. Liegt Shopware — wie in
den meisten Setups — in einem Unterordner (z. B. `shopware/`), musst du im Container **in genau
diesen Ordner wechseln**. `ddev exec -s playwright ...` läuft sonst immer im Projekt-Root
(`/var/www/html`) und findet deine `package.json` nicht:

```bash
ddev exec -s playwright sh -c "cd shopware && npm install"
```

Passe `shopware` an den Ordner an, in dem deine `package.json` liegt. Liegt sie direkt im
Projekt-Root, genügt `ddev exec -s playwright npm install`.

> **Warum das `cd`?** Der `ddev playwright`-Wrapper übernimmt automatisch dein aktuelles
> Host-Verzeichnis (`HostWorkingDir`) und mappt es in den Container — deshalb reicht dort später ein
> einfaches `cd shopware && ddev playwright test`. `ddev exec` kennt dieses Mapping aber nicht und
> startet immer im Container-Root, daher hier das explizite `cd`.

> **Nur `node_modules`, keine Browser:** `npm install` installiert ausschließlich die
> JavaScript-Abhängigkeiten (`node_modules`). Die Browser musst du **nicht** installieren — sie sind
> im Container bereits vorhanden (siehe nächster Kasten).

### Browser sind im Container bereits vorhanden

Du brauchst **keinen** Browser-Installationsschritt — also **kein** `npx playwright install` und
**kein** `ddev playwright install`. Das Add-on nutzt das offizielle
`mcr.microsoft.com/playwright`-Image, in dem alle Browser (Chromium, Firefox, WebKit) bereits unter
`/ms-playwright` vorinstalliert sind. Die vom Add-on gesetzte Umgebungsvariable
`PLAYWRIGHT_BROWSERS_PATH=/ms-playwright` zeigt Playwright genau dorthin.

Wenn Playwright trotzdem meldet, es seien **keine Browser installiert** (z. B. beim ersten Start des
UI-Modus oder als Fehler `Executable doesn't exist`), liegt das **nicht** an fehlenden Browsern,
sondern an einem **Versions-Mismatch**: Deine `@playwright/test`-Version erwartet eine andere
Browser-Version, als das Image mitbringt.

- **Löse das nicht** mit `ddev playwright install`. Das lädt die Browser zwar nach, aber **nicht
  dauerhaft** — nach dem nächsten `ddev restart` sind sie wieder weg, und du müsstest es „jedesmal"
  erneut tun.
- **Löse es stattdessen**, indem du `@playwright/test` und den Image-Tag auf dieselbe Version
  bringst (siehe Kasten in [Schritt 4](#4-packagejson-anlegen-und-abhängigkeiten-installieren)).

Zum Prüfen, dass die Browser im Container liegen:

```bash
ddev exec -s playwright sh -c "ls /ms-playwright"
```

## 5. `playwright.config.js` übernehmen

Lege neben deiner `package.json` eine `playwright.config.js` ab. Die fertige Konfiguration unter
[`examples/shopware/playwright.config.js`](../examples/shopware/playwright.config.js) funktioniert
**out of the box** und muss in der Regel **nicht angepasst** werden. Sie:

* lädt die Zugangsdaten aus `.env.local`,
* leitet die Basis-URL aus dem DDEV-Container ab (`VIRTUAL_HOST`),
* setzt Deutsch als Admin-Sprache,
* registriert automatisch **ein Playwright-Projekt pro Plugin und App**, indem sie nach
  `tests/e2e`-Ordnern in `custom/apps/*` und `custom/static-plugins/*` sucht.

Kopiere die Datei einfach neben deine `package.json`.

Weil die Config getrennt über `custom/apps/*` und `custom/static-plugins/*` iteriert, **sortiert
Playwright deine Tests automatisch nach `apps` und `static-plugins`** — sowohl im UI-Modus als auch
im Report. Du siehst dort also zwei Gruppen mit jeweils einem Projekt pro App bzw. Plugin, ohne dass
du dafür etwas konfigurieren musst:

```
▾ apps
  ▸ FfShopMonitoring
▾ static-plugins
  ▸ FfCleverReach
  ▸ FfContentPlus
```

## 6. Tests in Plugins und Apps schreiben

Playwright sucht **case-insensitiv** nach einem `tests/e2e`-Ordner in jedem Plugin bzw. jeder App.
Lege deine Tests genau dort ab:

| Typ        | Ordnerstruktur                                   |
| ---------- | ------------------------------------------------ |
| **App**    | `custom/apps/<APP-NAME>/Tests/E2E/`              |
| **Plugin** | `custom/static-plugins/<PLUGIN-NAME>/tests/E2E/` |

Da die Suche case-insensitiv ist, funktionieren sowohl `tests/e2e` als auch `Tests/E2E`. Wähle die
Schreibweise, die zu den Konventionen des jeweiligen Plugins/der App passt.

Jede `*.spec.js`-Datei in diesem Ordner wird automatisch als eigenes Projekt aufgenommen — du musst
die Konfiguration nicht anfassen, wenn du ein neues Plugin oder eine neue App mit Tests versiehst.

## 7. Tests ausführen

Führe die Befehle **aus dem Ordner mit der `package.json`** aus:

```bash
# Alle Tests
ddev playwright test

# Nur die Tests eines Plugins bzw. einer App (Projektname = Ordnername)
ddev playwright test --project "MeinPlugin"

# UI-Modus im Browser
ddev playwright --ui
```

Der UI-Modus ist danach unter `https://<projekt>.ddev.site:8078` erreichbar, der HTML-Report unter
`https://<projekt>.ddev.site:9324`.

## Beispieltests

Fertige Beispiele findest du unter [`examples/shopware/tests`](../examples/shopware/tests):

* [`admin-login.spec.js`](../examples/shopware/tests/admin-login.spec.js) — meldet sich in der
  Administration an und prüft, dass das Dashboard erscheint.
* [`admin-product-list.spec.js`](../examples/shopware/tests/admin-product-list.spec.js) — navigiert
  nach dem Login in die Produktliste.

Beide nutzen die `AdminPage`-Fixture der Acceptance-Test-Suite. Sie meldet sich mithilfe der
Integration (Access Key + Secret aus `.env.local`) **automatisch** an — du gibst also weder
Benutzername noch Passwort im Test an:

```js
import { test, expect } from '@shopware-ag/acceptance-test-suite';

test('meldet sich in der Administration an und zeigt das Dashboard', async ({ AdminPage }) => {
    await AdminPage.goto('/admin#/sw/dashboard/index');
    await expect(AdminPage.locator('.sw-admin-menu')).toBeVisible({ timeout: 30_000 });
});
```

Kopiere die Beispieldateien in den `tests/e2e`-Ordner deines Plugins bzw. deiner App und passe sie
an deinen Anwendungsfall an.
