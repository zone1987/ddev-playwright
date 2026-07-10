import { defineConfig, devices } from '@playwright/test';
import dotenv from 'dotenv';
import { fileURLToPath } from 'node:url';
import { dirname, resolve, join } from 'node:path';
import fs from 'node:fs';

const rootDir = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: resolve(rootDir, '.env.local') });

const baseURL = 'https://' + process.env.VIRTUAL_HOST.replace(/\/+$/, '') + '/';
process.env.APP_URL = baseURL;
process.env.LANG = 'de-DE';

const getDirProjects = (dir) => {
    dir = resolve(rootDir, dir);
    return fs
        .readdirSync(dir, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => {
            const testDir = join(dir, entry.name, 'tests', 'e2e');
            if (!fs.existsSync(testDir)) return null;
            return {
                name: `${entry.name}`,
                testDir,
                outputDir: join(dir, entry.name, 'playwright-results')
            };
        })
        .filter(Boolean);
}

const projects = [
    ...getDirProjects('custom/apps'),
    ...getDirProjects('custom/static-plugins'),
];

export default defineConfig({
    projects,
    timeout: 180_000,
    fullyParallel: true,
    use: {
        ...devices['Desktop Chrome'],
        baseURL,
        ignoreHTTPSErrors: true,
        locale: 'de-DE',
        timezoneId: 'Europe/Berlin',
        trace: 'on',
        screenshot: 'on',
        video: 'retain-on-failure',
    },
});
