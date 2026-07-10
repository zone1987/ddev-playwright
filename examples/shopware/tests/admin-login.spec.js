import { test, expect } from '@shopware-ag/acceptance-test-suite';

/**
 * Example test: logging in to the Shopware Administration.
 *
 * The `AdminPage` fixture from the acceptance test suite authenticates
 * automatically via the Admin API (SHOPWARE_ACCESS_KEY_ID /
 * SHOPWARE_SECRET_ACCESS_KEY) and hands you an already logged-in Playwright
 * page. So you don't have to provide a username or password in the test.
 */
test('logs in to the Administration and shows the dashboard', async ({ AdminPage }) => {
    // Jump straight to the dashboard — the login has already happened by now.
    await AdminPage.goto('/admin#/sw/dashboard/index');

    // The admin menu bar is only visible after a successful login.
    await expect(AdminPage.locator('.sw-admin-menu')).toBeVisible({ timeout: 30_000 });
});
