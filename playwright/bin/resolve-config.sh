#!/usr/bin/env bash
#ddev-generated
#
# Resolve the Playwright add-on configuration on the HOST, before DDEV renders
# the docker-compose file. Reads .ddev/playwright.yaml (deep-merged on top of
# .ddev/playwright/defaults.yaml) and writes two generated files:
#
#   .ddev/.env.playwright         -> PLAYWRIGHT_DOCKER_IMAGE / PLAYWRIGHT_VERSION
#                                    (consumed by docker-compose interpolation)
#   .ddev/playwright/paths.json   -> resolved manifest imported by the TS config
#
# Portability: uses ONLY POSIX sh/grep/sed by default, so it runs identically on
# macOS, Linux, WSL2 and Git-Bash. If a real `yq` binary is on PATH it is used
# for a proper deep-merge, but no Docker / volume mount is ever required (that is
# fragile on Windows). Written for bash 3.2 (no mapfile / associative arrays).
#
# Robustness contract: this script MUST NOT abort a `ddev start`. On any error it
# falls back to the "latest" image and shipped defaults.

set -u

# --- locate directories ---------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
# script lives at .ddev/playwright/bin/resolve-config.sh
PW_DIR="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"   # .ddev/playwright
DDEV_DIR="$(cd "${PW_DIR}/.." >/dev/null 2>&1 && pwd)"     # .ddev

# The user-editable config lives prominently at .ddev/playwright.yaml; the shipped
# defaults it is merged onto stay in .ddev/playwright/.
USER_CONFIG="${DDEV_DIR}/playwright.yaml"
DEFAULTS_CONFIG="${PW_DIR}/defaults.yaml"
# The resolved manifest lives beside them.
MANIFEST_FILE="${PW_DIR}/paths.json"
# .env.playwright MUST stay in .ddev/ — DDEV only interpolates .ddev/.env.* into
# docker-compose. It carries no #ddev-generated marker (avoids a restart warning);
# removal_actions delete it by filename.
ENV_FILE="${DDEV_DIR}/.env.playwright"

DEFAULT_IMAGE_LATEST="mcr.microsoft.com/playwright:latest"
# Empty by default — the user opts in to searchPaths in their own playwright.yaml.
HARDCODED_SEARCHPATHS='[]'

# --- helpers --------------------------------------------------------------------

# Strip a trailing CR (handles files checked out with CRLF on Windows).
strip_cr() { tr -d '\r'; }

# Flat-YAML scalar reader for a single key under `playwright:`. Restricted to the
# `playwright:` block so the top-level `version: 1` (schema version) is never
# confused with `playwright.version`. Handles quoted/unquoted values + comments.
grep_scalar() {
  key="$1"; file="$2"
  [ -f "${file}" ] || return 0
  sed -n '/^playwright:/,/^[^[:space:]#]/p' "${file}" 2>/dev/null \
    | sed -n "s/^[[:space:]]\{1,\}${key}:[[:space:]]*//p" \
    | head -n1 \
    | strip_cr \
    | sed 's/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//' \
    | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'
}

# Read a scalar with user-then-defaults fallback.
read_key() {
  flat_key="$1"
  value="$(grep_scalar "${flat_key}" "${USER_CONFIG}")"
  [ -z "${value}" ] && value="$(grep_scalar "${flat_key}" "${DEFAULTS_CONFIG}")"
  printf '%s' "${value}"
}

# Build a JSON array from a YAML file's `<key>:` list block (the "  - item" lines
# under it). Returns 1 if the key is absent or the list is empty.
list_json_from() {
  key="$1" file="$2"
  [ -f "${file}" ] || return 1
  grep -q "${key}:" "${file}" 2>/dev/null || return 1
  items="$(sed -n "/^[[:space:]]*${key}:/,/^[[:space:]]*[a-zA-Z_]*:[[:space:]]*\$/p" "${file}" 2>/dev/null \
    | sed -n 's/^[[:space:]]*-[[:space:]]*//p' \
    | strip_cr \
    | sed 's/[[:space:]]*#.*$//; s/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//; s/[[:space:]]*$//')"
  [ -n "${items}" ] || return 1
  out="["
  first=1
  while IFS= read -r item; do
    [ -z "${item}" ] && continue
    if [ "${first}" -eq 1 ]; then first=0; else out="${out},"; fi
    out="${out}\"${item}\""
  done <<EOF
${items}
EOF
  out="${out}]"
  printf '%s' "${out}"
}

# --- optional: real yq deep-merge (only if a yq binary is on PATH) --------------
# No Docker, no volume mounts. Purely a nicety when the maintainer has yq locally.
YQ_MERGED=""
if command -v yq >/dev/null 2>&1; then
  if [ -f "${DEFAULTS_CONFIG}" ] && [ -f "${USER_CONFIG}" ]; then
    YQ_MERGED="$(yq eval-all 'select(fileIndex==0) * select(fileIndex==1)' \
      "${DEFAULTS_CONFIG}" "${USER_CONFIG}" 2>/dev/null)"
  elif [ -f "${USER_CONFIG}" ]; then
    YQ_MERGED="$(yq '.' "${USER_CONFIG}" 2>/dev/null)"
  elif [ -f "${DEFAULTS_CONFIG}" ]; then
    YQ_MERGED="$(yq '.' "${DEFAULTS_CONFIG}" 2>/dev/null)"
  fi
fi

yq_read() {
  # yq_read <path>; echoes value or empty. Only used when YQ_MERGED is set.
  [ -n "${YQ_MERGED}" ] || return 1
  printf '%s\n' "${YQ_MERGED}" | yq "$1 // \"\"" 2>/dev/null | strip_cr
}

# --- resolve scalars ------------------------------------------------------------
if [ -n "${YQ_MERGED}" ]; then
  VERSION="$(yq_read '.playwright.version')"
  INSTANCE_CONFIG="$(yq_read '.playwright.instanceConfig')"
  TEST_DIRECTORY="$(yq_read '.playwright.testDirectory')"
  MERGE_STRATEGY="$(yq_read '.playwright.mergeStrategy')"
else
  VERSION="$(read_key 'version')"
  INSTANCE_CONFIG="$(read_key 'instanceConfig')"
  TEST_DIRECTORY="$(read_key 'testDirectory')"
  MERGE_STRATEGY="$(read_key 'mergeStrategy')"
fi

# Sensible hard defaults if everything above failed.
[ -z "${INSTANCE_CONFIG}" ] || [ "${INSTANCE_CONFIG}" = "null" ] && INSTANCE_CONFIG="tests/playwright.config.ts"
[ -z "${TEST_DIRECTORY}" ] || [ "${TEST_DIRECTORY}" = "null" ] && TEST_DIRECTORY="tests/e2e"
[ -z "${MERGE_STRATEGY}" ] || [ "${MERGE_STRATEGY}" = "null" ] && MERGE_STRATEGY="deep"

# --- resolve searchPaths (array) ------------------------------------------------
SEARCH_PATHS_JSON=""
if [ -n "${YQ_MERGED}" ]; then
  SEARCH_PATHS_JSON="$(printf '%s\n' "${YQ_MERGED}" | yq -o=json -I=0 '.playwright.searchPaths // []' 2>/dev/null | strip_cr)"
fi
if [ -z "${SEARCH_PATHS_JSON}" ] || [ "${SEARCH_PATHS_JSON}" = "null" ] || [ "${SEARCH_PATHS_JSON}" = "[]" ]; then
  # POSIX fallback: user file first, then defaults, then hardcoded set.
  SEARCH_PATHS_JSON="$(list_json_from searchPaths "${USER_CONFIG}")" \
    || SEARCH_PATHS_JSON="$(list_json_from searchPaths "${DEFAULTS_CONFIG}")" \
    || SEARCH_PATHS_JSON="${HARDCODED_SEARCHPATHS}"
fi
[ -z "${SEARCH_PATHS_JSON}" ] && SEARCH_PATHS_JSON="${HARDCODED_SEARCHPATHS}"

# --- resolve extra packages (array) ---------------------------------------------
# User-declared npm packages to install alongside @playwright/test.
PACKAGES_JSON=""
if [ -n "${YQ_MERGED}" ]; then
  PACKAGES_JSON="$(printf '%s\n' "${YQ_MERGED}" | yq -o=json -I=0 '.playwright.packages // []' 2>/dev/null | strip_cr)"
fi
if [ -z "${PACKAGES_JSON}" ] || [ "${PACKAGES_JSON}" = "null" ]; then
  PACKAGES_JSON="$(list_json_from packages "${USER_CONFIG}")" || PACKAGES_JSON="[]"
fi
[ -z "${PACKAGES_JSON}" ] && PACKAGES_JSON="[]"

# --- derive image tag -----------------------------------------------------------
if [ -z "${VERSION}" ] || [ "${VERSION}" = "null" ]; then
  IMAGE="${DEFAULT_IMAGE_LATEST}"
  VERSION_OUT="latest"
else
  IMAGE="mcr.microsoft.com/playwright:v${VERSION}-noble"
  VERSION_OUT="${VERSION}"
fi

# --- detect Shopware (CMS-agnostic core stays CMS-agnostic) ---------------------
# "auto" (default): a project is Shopware if a composer.json requiring
# shopware/core is found in the project root, the DDEV docroot, or a common
# subfolder (Shopware is not always at the project root). Override with
# `playwright.shopware: true|false` in playwright.yaml.
SHOPWARE_FLAG="$(read_key 'shopware')"
SHOPWARE_ROOT_CFG="$(read_key 'shopwareRoot')"
if [ -n "${YQ_MERGED}" ]; then
  SHOPWARE_FLAG="$(yq_read '.playwright.shopware')"
  SHOPWARE_ROOT_CFG="$(yq_read '.playwright.shopwareRoot')"
fi

PROJECT_ROOT="$(cd "${DDEV_DIR}/.." >/dev/null 2>&1 && pwd)"

# Read the DDEV docroot (if configured) so we also probe there.
DOCROOT=""
if [ -f "${DDEV_DIR}/config.yaml" ]; then
  DOCROOT="$(sed -n 's/^docroot:[[:space:]]*//p' "${DDEV_DIR}/config.yaml" 2>/dev/null | head -n1 | strip_cr | sed 's/^"//; s/"$//')"
fi

# Candidate subfolders probed for Shopware. An explicit shopwareRoot from the
# config is tried FIRST — the safety net when Shopware lives in an unusual place
# the auto-detection doesn't know about.
SW_CANDIDATES="${SHOPWARE_ROOT_CFG} ${DOCROOT} shopware docroot public app src web html"

detect_shopware() {
  # "" = project root. Probe each candidate for a shopware/core composer.json.
  for cand in "" ${SW_CANDIDATES}; do
    [ -z "${cand}" ] && cf="${PROJECT_ROOT}/composer.json" || cf="${PROJECT_ROOT}/${cand}/composer.json"
    if [ -f "${cf}" ] && grep -q '"shopware/core"' "${cf}" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

IS_SHOPWARE="false"
case "${SHOPWARE_FLAG}" in
  true|True|TRUE) IS_SHOPWARE="true" ;;
  false|False|FALSE) IS_SHOPWARE="false" ;;
  *) detect_shopware && IS_SHOPWARE="true" ;;
esac

# --- detect WordPress (additive; core stays CMS-agnostic) -----------------------
# "auto" (default): a project is WordPress if wp-load.php / wp-settings.php /
# wp-includes/version.php is found in the project root, the DDEV docroot, or a
# common subfolder, OR the DDEV project type is "wordpress". Override with
# `playwright.wordpress: true|false` and `playwright.wordpressRoot` in playwright.yaml.
WORDPRESS_FLAG="$(read_key 'wordpress')"
WORDPRESS_ROOT_CFG="$(read_key 'wordpressRoot')"
if [ -n "${YQ_MERGED}" ]; then
  WORDPRESS_FLAG="$(yq_read '.playwright.wordpress')"
  WORDPRESS_ROOT_CFG="$(yq_read '.playwright.wordpressRoot')"
fi

# DDEV project type (a strong WordPress signal).
DDEV_TYPE=""
if [ -f "${DDEV_DIR}/config.yaml" ]; then
  DDEV_TYPE="$(sed -n 's/^type:[[:space:]]*//p' "${DDEV_DIR}/config.yaml" 2>/dev/null | head -n1 | strip_cr | sed 's/^"//; s/"$//')"
fi

WP_CANDIDATES="${WORDPRESS_ROOT_CFG} ${DOCROOT} wp web/wp wordpress public docroot web html"

detect_wordpress() {
  [ "${DDEV_TYPE}" = "wordpress" ] && return 0
  for cand in "" ${WP_CANDIDATES}; do
    [ -z "${cand}" ] && base="${PROJECT_ROOT}" || base="${PROJECT_ROOT}/${cand}"
    if [ -f "${base}/wp-load.php" ] || [ -f "${base}/wp-settings.php" ] || [ -f "${base}/wp-includes/version.php" ]; then
      return 0
    fi
  done
  return 1
}

IS_WORDPRESS="false"
case "${WORDPRESS_FLAG}" in
  true|True|TRUE) IS_WORDPRESS="true" ;;
  false|False|FALSE) IS_WORDPRESS="false" ;;
  *) detect_wordpress && IS_WORDPRESS="true" ;;
esac

# --- Shopware env passthrough ---------------------------------------------------
# When a CMS is detected, forward its test-suite variables into the playwright
# container via .env.playwright (DDEV interpolates .ddev/.env.* into docker-compose).
# Values are read from the project .env if present; base URLs fall back to
# DDEV_PRIMARY_URL, but a user-set value always wins.
# The .env may live in a subfolder, so probe both CMS candidate sets. We resolve
# the project .env DIRECTORY (the first candidate that has a .env or .env.local),
# then read values with Symfony precedence: .env.local overrides .env. This lets
# users keep secrets (e.g. SHOPWARE_ACCESS_KEY_ID) out of git in .env.local.
PROJECT_ENV_DIR=""
for cand in "" ${SW_CANDIDATES} ${WP_CANDIDATES}; do
  [ -z "${cand}" ] && dir="${PROJECT_ROOT}" || dir="${PROJECT_ROOT}/${cand}"
  if [ -f "${dir}/.env" ] || [ -f "${dir}/.env.local" ]; then PROJECT_ENV_DIR="${dir}"; break; fi
done
env_value_from() {
  # env_value_from <FILE> <KEY> — read KEY=value from FILE (last wins), strip quotes/CR.
  file="$1"; key="$2"
  [ -f "${file}" ] || return 0
  sed -n "s/^[[:space:]]*${key}=//p" "${file}" 2>/dev/null \
    | tail -n1 | strip_cr | sed 's/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//'
}
env_value() {
  # env_value <KEY> — .env.local takes precedence over .env (Symfony convention).
  key="$1"
  [ -n "${PROJECT_ENV_DIR}" ] || return 0
  val="$(env_value_from "${PROJECT_ENV_DIR}/.env.local" "${key}")"
  [ -z "${val}" ] && val="$(env_value_from "${PROJECT_ENV_DIR}/.env" "${key}")"
  printf '%s' "${val}"
}

# Shopware acceptance-test-suite variables. Integration auth only
# (SHOPWARE_ACCESS_KEY_ID / SHOPWARE_SECRET_ACCESS_KEY). Source:
# https://developer.shopware.com/docs/guides/development/testing/e2e-playwright/install-configure.html
SW_APP_URL=""
SW_AKID=""; SW_SAK=""
if [ "${IS_SHOPWARE}" = "true" ]; then
  SW_APP_URL="$(env_value 'APP_URL')"
  [ -z "${SW_APP_URL}" ] && SW_APP_URL="${DDEV_PRIMARY_URL:-}"
  SW_AKID="$(env_value 'SHOPWARE_ACCESS_KEY_ID')"
  SW_SAK="$(env_value 'SHOPWARE_SECRET_ACCESS_KEY')"
fi

# WordPress @wordpress/e2e-test-utils-playwright variables. Tests run against the
# running DDEV instance (not wp-env). WP_BASE_URL falls back to DDEV_PRIMARY_URL;
# credentials default to the DDEV WordPress admin (admin / password). Source:
# https://developer.wordpress.org/news/2026/05/getting-started-writing-wordpress-e2e-tests-with-playwright/
WP_BASE_URL=""; WP_USER=""; WP_PASS=""
if [ "${IS_WORDPRESS}" = "true" ]; then
  WP_BASE_URL="$(env_value 'WP_BASE_URL')"
  [ -z "${WP_BASE_URL}" ] && WP_BASE_URL="${DDEV_PRIMARY_URL:-}"
  WP_USER="$(env_value 'WP_USERNAME')"
  [ -z "${WP_USER}" ] && WP_USER="admin"
  WP_PASS="$(env_value 'WP_PASSWORD')"
  [ -z "${WP_PASS}" ] && WP_PASS="password"
fi

# --- write .env.playwright ------------------------------------------------------
# No #ddev-generated marker here: DDEV would warn about an "unexpected" marker in
# an env file on every restart. This file is regenerated on every start anyway.
{
  printf 'PLAYWRIGHT_DOCKER_IMAGE=%s\n' "${IMAGE}"
  printf 'PLAYWRIGHT_VERSION=%s\n' "${VERSION_OUT}"
  printf 'PLAYWRIGHT_IS_SHOPWARE=%s\n' "${IS_SHOPWARE}"
  printf 'PLAYWRIGHT_IS_WORDPRESS=%s\n' "${IS_WORDPRESS}"
  if [ "${IS_SHOPWARE}" = "true" ]; then
    printf 'APP_URL=%s\n' "${SW_APP_URL}"
    printf 'SHOPWARE_ACCESS_KEY_ID=%s\n' "${SW_AKID}"
    printf 'SHOPWARE_SECRET_ACCESS_KEY=%s\n' "${SW_SAK}"
  fi
  if [ "${IS_WORDPRESS}" = "true" ]; then
    printf 'WP_BASE_URL=%s\n' "${WP_BASE_URL}"
    printf 'WP_USERNAME=%s\n' "${WP_USER}"
    printf 'WP_PASSWORD=%s\n' "${WP_PASS}"
  fi
} > "${ENV_FILE}"

# --- write playwright.paths.json manifest --------------------------------------
{
  printf '{\n'
  printf '  "//": "#ddev-generated",\n'
  printf '  "version": "%s",\n' "${VERSION_OUT}"
  printf '  "searchPaths": %s,\n' "${SEARCH_PATHS_JSON}"
  printf '  "instanceConfig": "%s",\n' "${INSTANCE_CONFIG}"
  printf '  "testDirectory": "%s",\n' "${TEST_DIRECTORY}"
  printf '  "mergeStrategy": "%s",\n' "${MERGE_STRATEGY}"
  printf '  "isShopware": %s,\n' "${IS_SHOPWARE}"
  printf '  "isWordpress": %s,\n' "${IS_WORDPRESS}"
  printf '  "packages": %s,\n' "${PACKAGES_JSON}"
  printf '  "baseURL": "http://web"\n'
  printf '}\n'
} > "${MANIFEST_FILE}"

echo "playwright: resolved image ${IMAGE} (version ${VERSION_OUT}); shopware=${IS_SHOPWARE} wordpress=${IS_WORDPRESS}"
exit 0
