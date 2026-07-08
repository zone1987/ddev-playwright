// #ddev-generated
//
// Instance discovery helper, run inside the playwright container:
//   node /mnt/ddev_config/playwright/bin/discover.mjs [--mode plain|classify]
//
// Default (plain): prints one discovered instance path (relative to the project
// root) per line.
//
// classify: prints one TAB-separated line per instance:
//     bundled   <relPath>                 (no own config → runs via global config)
//     standalone<TAB><relPath><TAB><absConfigPath>   (has its own playwright.config)
//
// Shares the discovery logic of the global config. Never throws: any error results
// in no output (exit 0), so an empty/misconfigured project is not an error.

import { statSync, readdirSync, readFileSync, existsSync } from 'node:fs';
import path from 'node:path';

const ROOT = '/var/www/html';
const MANIFEST = '/mnt/ddev_config/playwright/paths.json';
const MODE = process.argv.includes('--mode')
  ? process.argv[process.argv.indexOf('--mode') + 1]
  : 'plain';

function loadManifest() {
  try {
    return JSON.parse(readFileSync(MANIFEST, 'utf8'));
  } catch {
    return { searchPaths: [], testDirectory: 'tests/e2e', instanceConfig: 'tests/playwright.config.ts' };
  }
}

function isDir(p) {
  try {
    return statSync(p).isDirectory();
  } catch {
    return false;
  }
}

function rd(p) {
  try {
    return readdirSync(p);
  } catch {
    return [];
  }
}

function hasSpec(dir) {
  const stack = [dir];
  while (stack.length) {
    const cur = stack.pop();
    for (const e of rd(cur)) {
      const f = path.join(cur, e);
      if (isDir(f)) stack.push(f);
      else if (/\.spec\.(ts|js|mts|cts|mjs|cjs)$/.test(e)) return true;
    }
  }
  return false;
}

// The instance's own config, if any (instanceConfig path, else a root-level
// playwright.config.* in the instance dir). Returns the absolute path or null.
function ownConfig(instDir, m) {
  const candidates = [
    path.join(instDir, m.instanceConfig || 'tests/playwright.config.ts'),
    path.join(instDir, 'playwright.config.ts'),
    path.join(instDir, 'playwright.config.js'),
    path.join(instDir, 'playwright.config.mjs'),
  ];
  for (const c of candidates) {
    try {
      if (existsSync(c)) return c;
    } catch {
      /* ignore */
    }
  }
  return null;
}

try {
  const m = loadManifest();
  const testDir = m.testDirectory || 'tests/e2e';
  for (const sp of m.searchPaths || []) {
    const abs = path.join(ROOT, sp);
    if (!isDir(abs)) continue;
    for (const entry of rd(abs)) {
      const inst = path.join(abs, entry);
      if (!isDir(inst)) continue;
      if (!(isDir(path.join(inst, testDir)) && hasSpec(path.join(inst, testDir)))) continue;
      const rel = path.relative(ROOT, inst);
      if (MODE === 'classify') {
        const cfg = ownConfig(inst, m);
        if (cfg) console.log(`standalone\t${rel}\t${cfg}`);
        else console.log(`bundled\t${rel}`);
      } else {
        console.log(rel);
      }
    }
  }
} catch {
  // stay silent — discovery failures must not surface as errors
}
