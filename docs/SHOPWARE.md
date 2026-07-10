# Playwright in Shopware projects

> 🇩🇪 Diese Anleitung gibt es auch auf Deutsch: [`SHOPWARE_DE.md`](SHOPWARE_DE.md).

This guide explains, step by step, how to set up the `ddev-playwright` add-on in a Shopware project
and write your first end-to-end tests.

> **Important:** Make sure **no other Playwright add-on** is installed in your DDEV project. Two
> parallel Playwright containers/wrappers cause conflicts (duplicate ports, competing
> `ddev playwright` commands). Check with `ddev add-on list` and remove any second Playwright add-on
> before you continue.

## Contents <!-- omit in toc -->

* [1. Install the add-on](#1-install-the-add-on)
* [2. Create an integration in Shopware](#2-create-an-integration-in-shopware)
* [3. Store the credentials in `.env.local`](#3-store-the-credentials-in-envlocal)
* [4. Create a `package.json` and install dependencies](#4-create-a-packagejson-and-install-dependencies)
  * [Browsers are already present in the container](#browsers-are-already-present-in-the-container)
* [5. Use the `playwright.config.js`](#5-use-the-playwrightconfigjs)
* [6. Write tests in plugins and apps](#6-write-tests-in-plugins-and-apps)
* [7. Run the tests](#7-run-the-tests)
* [Example tests](#example-tests)

## 1. Install the add-on

In your project root:

```bash
ddev add-on get zone1987/ddev-playwright
ddev restart
```

Afterwards, commit the `.ddev` directory to version control.

## 2. Create an integration in Shopware

The tests authenticate through the **Admin API**. For that you need an integration with an access
key and a secret.

1. Log in to the **Shopware Administration**.
2. Open **Settings → System → Integrations**.
3. Click **Add integration** in the top right.
4. Give it a name, e.g. `Playwright E2E`.
5. **Enable the "Administrator" option** (admin permissions). Without admin rights the test login
   fails, because the acceptance test suite accesses the full Admin API.
6. Click **Save integration**.
7. Shopware now shows you the **Access Key ID** and the **Secret Access Key**.

   > ⚠️ **The secret access key is shown only once.** Copy it immediately. If you lose it, you have
   > to regenerate it in the integration.

## 3. Store the credentials in `.env.local`

The acceptance test suite reads its credentials from **environment variables**. Put them in a
**`.env.local`** file next to your `package.json` (see the next step for where the `package.json`
lives). In Shopware this file is already git-ignored and is the right place for secrets:

```bash
# .env.local
SHOPWARE_ACCESS_KEY_ID="<your-access-key-id>"
SHOPWARE_SECRET_ACCESS_KEY="<your-secret-access-key>"
```

Enter the two values from step 2 here.

## 4. Create a `package.json` and install dependencies

In the **Shopware folder** (where `custom/` lives — i.e. the folder that is the Shopware root),
create a `package.json`. A ready-to-use template is available at
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

`"type": "module"` is required because the example config uses `import` syntax.

> **Important — the version must match the image:** The `@playwright/test` version **must** match
> the container's Playwright image exactly (`PLAYWRIGHT_IMAGE_TAG` in `.ddev/.env`, default
> `v1.56.1-noble`). That is why `1.56.1` is pinned above (without `^`). If the versions differ,
> Playwright looks for a browser version that isn't in the image — see
> [Browsers are already present in the container](#browsers-are-already-present-in-the-container).
>
> If you want to use a different version, set the matching image tag and pin the same version in the
> `package.json`:
>
> ```bash
> ddev dotenv set .ddev/.env --playwright-image-tag v1.57.0-noble
> ddev restart
> ```

Then install the dependencies through the Playwright container. If Shopware lives in a subfolder
(e.g. `shopware/`) — as in most setups — you have to **change into exactly that folder** inside the
container. Otherwise `ddev exec -s playwright ...` always runs in the project root
(`/var/www/html`) and won't find your `package.json`:

```bash
ddev exec -s playwright sh -c "cd shopware && npm install"
```

Adjust `shopware` to the folder where your `package.json` lives. If it sits directly in the project
root, `ddev exec -s playwright npm install` is enough.

> **Why the `cd`?** The `ddev playwright` wrapper automatically picks up your current host directory
> (`HostWorkingDir`) and maps it into the container — that's why a simple `cd shopware && ddev
> playwright test` is enough later. `ddev exec` does not know about this mapping and always starts in
> the container root, hence the explicit `cd` here.

> **Only `node_modules`, no browsers:** `npm install` installs only the JavaScript dependencies
> (`node_modules`). You do **not** need to install the browsers — they are already present in the
> container (see the next box).

### Browsers are already present in the container

You do **not** need a browser installation step — so **no** `npx playwright install` and **no**
`ddev playwright install`. The add-on uses the official `mcr.microsoft.com/playwright` image, in
which all browsers (Chromium, Firefox, WebKit) are already preinstalled under `/ms-playwright`. The
`PLAYWRIGHT_BROWSERS_PATH=/ms-playwright` environment variable set by the add-on points Playwright
straight there.

If Playwright still reports that **no browsers are installed** (e.g. on the first launch of UI mode,
or as the error `Executable doesn't exist`), this is **not** due to missing browsers but to a
**version mismatch**: your `@playwright/test` version expects a different browser version than the
image ships.

- **Do not fix this** with `ddev playwright install`. That does download the browsers, but **not
  persistently** — after the next `ddev restart` they are gone again, and you would have to repeat it
  "every time".
- **Fix it instead** by aligning `@playwright/test` and the image tag to the same version (see the
  box in [step 4](#4-create-a-packagejson-and-install-dependencies)).

To verify the browsers are in the container:

```bash
ddev exec -s playwright sh -c "ls /ms-playwright"
```

## 5. Use the `playwright.config.js`

Place a `playwright.config.js` next to your `package.json`. The ready-made config at
[`examples/shopware/playwright.config.js`](../examples/shopware/playwright.config.js) works **out of
the box** and usually does **not** need to be changed. It:

* loads the credentials from `.env.local`,
* derives the base URL from the DDEV container (`VIRTUAL_HOST`),
* sets German as the admin language,
* automatically registers **one Playwright project per plugin and app** by looking for `tests/e2e`
  folders under `custom/apps/*` and `custom/static-plugins/*`.

Just copy the file next to your `package.json`.

Because the config iterates over `custom/apps/*` and `custom/static-plugins/*` separately,
**Playwright automatically sorts your tests into `apps` and `static-plugins`** — both in UI mode and
in the report. You therefore see two groups, each with one project per app or plugin, without having
to configure anything:

```
▾ apps
  ▸ FfShopMonitoring
▾ static-plugins
  ▸ FfCleverReach
  ▸ FfContentPlus
```

## 6. Write tests in plugins and apps

Playwright searches **case-insensitively** for a `tests/e2e` folder in each plugin or app. Put your
tests exactly there:

| Type       | Folder structure                                 |
| ---------- | ------------------------------------------------ |
| **App**    | `custom/apps/<APP-NAME>/Tests/E2E/`              |
| **Plugin** | `custom/static-plugins/<PLUGIN-NAME>/tests/E2E/` |

Since the search is case-insensitive, both `tests/e2e` and `Tests/E2E` work. Pick the spelling that
matches the conventions of the respective plugin/app.

Every `*.spec.js` file in that folder is automatically picked up as its own project — you don't have
to touch the configuration when you add tests to a new plugin or app.

## 7. Run the tests

Run the commands **from the folder that contains the `package.json`**:

```bash
# All tests
ddev playwright test

# Only the tests of one plugin or app (project name = folder name)
ddev playwright test --project "MyPlugin"

# UI mode in the browser
ddev playwright --ui
```

UI mode is then reachable at `https://<project>.ddev.site:8078`, the HTML report at
`https://<project>.ddev.site:9324`.

## Example tests

Ready-to-use examples are available under [`examples/shopware/tests`](../examples/shopware/tests):

* [`admin-login.spec.js`](../examples/shopware/tests/admin-login.spec.js) — logs in to the
  Administration and checks that the dashboard appears.
* [`admin-product-list.spec.js`](../examples/shopware/tests/admin-product-list.spec.js) — navigates
  to the product list after logging in.

Both use the `AdminPage` fixture from the acceptance test suite. It logs in **automatically** using
the integration (access key + secret from `.env.local`) — so you provide neither username nor
password in the test:

```js
import { test, expect } from '@shopware-ag/acceptance-test-suite';

test('logs in to the Administration and shows the dashboard', async ({ AdminPage }) => {
    await AdminPage.goto('/admin#/sw/dashboard/index');
    await expect(AdminPage.locator('.sw-admin-menu')).toBeVisible({ timeout: 30_000 });
});
```

Copy the example files into the `tests/e2e` folder of your plugin or app and adapt them to your use
case.
