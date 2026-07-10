import { test, expect } from '@shopware-ag/acceptance-test-suite';

/**
 * Example test: navigating the admin and asserting something.
 *
 * Builds on the same automatic login of the `AdminPage` fixture and opens the
 * product list. Shows how to navigate to a specific admin page after login and
 * verify its content.
 */
test('opens the product list in the admin', async ({ AdminPage }) => {
    await AdminPage.goto('/admin#/sw/product/index');

    // The product listing grid appears once the module has loaded. We assert on
    // structural selectors rather than visible text so the test stays independent
    // of the admin language (the example config runs the admin in German).
    await expect(AdminPage.locator('.smart-bar__header')).toBeVisible({ timeout: 30_000 });
    await expect(AdminPage.locator('.sw-product-list__content')).toBeVisible();
});
