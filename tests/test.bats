#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs
#
# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'

setup() {
  set -eu -o pipefail

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
  # The playwright service must be up.
  run ddev exec -s playwright echo ok
  assert_success
  assert_output --partial "ok"

  # The official image ships the browsers preinstalled under /ms-playwright.
  run ddev exec -s playwright sh -c 'ls /ms-playwright | grep -c chromium'
  assert_success
  refute_output "0"
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
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

@test "default image tag is applied" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  # The container runs a concrete Playwright image (default tag), not an empty ref.
  run ddev exec -s playwright sh -c 'echo "${PLAYWRIGHT_BROWSERS_PATH:-}"'
  assert_success
  assert_output --partial "/ms-playwright"
}

@test "image tag can be pinned via .ddev/.env" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  printf 'PLAYWRIGHT_IMAGE_TAG=v1.56.1-noble\n' > "${TESTDIR}/.ddev/.env"
  run ddev restart -y
  assert_success
  # The pin controls the Docker image tag: the running container uses exactly it.
  run docker inspect --format '{{.Config.Image}}' "ddev-${PROJNAME}-playwright"
  assert_success
  assert_output --partial "mcr.microsoft.com/playwright:v1.56.1-noble"
}

@test "CLI passthrough works" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  # A project with @playwright/test installed can run the CLI through the wrapper.
  ddev exec -s playwright sh -c 'cd /var/www/html && npm init -y >/dev/null 2>&1 && npm install --no-audit --no-fund --silent -D @playwright/test@1.56.1'
  run ddev playwright --version
  assert_success
  assert_output --partial "1.56.1"
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
