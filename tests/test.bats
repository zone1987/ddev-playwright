#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs

# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

setup() {
  set -eu -o pipefail

  # Override this variable for your add-on:
  export GITHUB_REPO=zone1987/ddev-playwright

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success
  run ddev start -y
  assert_success
}

health_checks() {
  # The playwright service must be up and the CLI available inside it.
  run ddev exec -s playwright npx playwright --version
  assert_success
  assert_output --partial "Version"

  # The version resolution must have produced the environment + manifest.
  assert_file_exist "${TESTDIR}/.ddev/.env.playwright"
  assert_file_exist "${TESTDIR}/.ddev/playwright/paths.json"
  assert_file_exist "${TESTDIR}/.ddev/playwright/config.ts"
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  # Persist TESTDIR if running inside GitHub Actions. Useful for uploading test result artifacts
  # See example at https://github.com/ddev/github-action-add-on-test#preserving-artifacts
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

@test "empty project does not error" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  # No test directories anywhere: discover and a test run must both exit 0.
  run ddev playwright discover
  assert_success
  assert_output --partial "No Playwright instances found"
  run ddev playwright
  assert_success
}

@test "nonexistent searchPaths do not error" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  # Point searchPaths at directories that do not exist.
  cat > "${TESTDIR}/.ddev/playwright.yaml" <<'EOF'
#ddev-generated
version: 1
playwright:
  searchPaths:
    - does/not/exist
    - also/missing
EOF
  run ddev restart -y
  assert_success
  run ddev playwright discover
  assert_success
  assert_output --partial "No Playwright instances found"
}

@test "one discovered instance" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  # searchPaths are empty by default, so opt in to custom/plugins explicitly.
  cat > "${TESTDIR}/.ddev/playwright.yaml" <<'EOF'
#ddev-generated
version: 1
playwright:
  searchPaths:
    - custom/plugins
EOF
  # Create a fake instance under that searchPath.
  mkdir -p "${TESTDIR}/custom/plugins/demo/tests/e2e"
  cat > "${TESTDIR}/custom/plugins/demo/tests/e2e/smoke.spec.ts" <<'EOF'
import { test, expect } from '@playwright/test';
test('noop', async () => { expect(1).toBe(1); });
EOF
  run ddev restart -y
  assert_success
  run ddev playwright discover
  assert_success
  assert_output --partial "custom/plugins/demo"
  run ddev playwright install
  assert_success
  # @axe-core/playwright is always installed (accessibility out of the box).
  run ddev exec -s playwright test -d /mnt/ddev_config/playwright/node_modules/@axe-core/playwright
  assert_success
  run ddev playwright
  assert_success
}

@test "standalone instance with its own config runs separately" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  cat > "${TESTDIR}/.ddev/playwright.yaml" <<'EOF'
#ddev-generated
version: 1
playwright:
  version: "1.56.1"
  searchPaths:
    - custom/plugins
EOF
  mkdir -p "${TESTDIR}/custom/plugins/own/tests/e2e"
  cat > "${TESTDIR}/custom/plugins/own/tests/playwright.config.ts" <<'EOF'
import { defineConfig, devices } from '@playwright/test';
import base from '/mnt/ddev_config/playwright/config.ts';
export default defineConfig({ ...base, testDir: './e2e',
  projects: [{ name: 'ff', use: { ...devices['Desktop Firefox'] } }] });
EOF
  cat > "${TESTDIR}/custom/plugins/own/tests/e2e/browser.spec.ts" <<'EOF'
import { test, expect } from '@playwright/test';
test('runs in firefox from the instance config', async ({ browserName }) => {
  expect(browserName).toBe('firefox');
});
EOF
  run ddev restart -y
  assert_success
  run ddev playwright install
  assert_success
  # The instance's own config (Firefox) must win — the test asserts browserName.
  run ddev playwright
  assert_success
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}
