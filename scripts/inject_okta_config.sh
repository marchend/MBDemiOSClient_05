#!/bin/bash
#
# inject_okta_config.sh
#
# postBuildScript phase that copies Okta configuration from the calling shell's
# environment into the built app's Info.plist. Runs after Xcode has produced
# ${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}, so any value we plutil-replace here
# overrides what was committed to the source Info.plist.
#
# Contract:
#   - For each OKTA_* env var that IS set, replace the matching plist key.
#   - For each OKTA_* env var that is NOT set, leave the source sentinel
#     (__OKTA_<KEY>_UNSET__) in place. The app's OktaConfig loader recognises
#     the sentinel and returns .notConfigured at runtime.
#
# This script MUST NEVER fail the build: a developer building the project
# without Okta credentials should still get a green build with a non-crashing
# "not configured" runtime state. CI / production builds set the env vars.
#
# Env vars consumed (all optional):
#   OKTA_ISSUER         e.g. https://example.okta.com/oauth2/default
#   OKTA_CLIENT_ID      OAuth client id
#   OKTA_REDIRECT_URI   e.g. com.acmebank.mobile://callback
#   OKTA_SCOPES         space-separated, e.g. "openid profile offline_access"

set -u

PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

if [ ! -f "${PLIST}" ]; then
  echo "warning: inject_okta_config.sh: Info.plist not found at ${PLIST}; skipping"
  exit 0
fi

inject() {
  local key="$1"
  local value="$2"
  if [ -n "${value}" ]; then
    plutil -replace "${key}" -string "${value}" "${PLIST}" || \
      echo "warning: inject_okta_config.sh: plutil -replace ${key} failed; leaving sentinel"
  fi
}

inject "OKTA_ISSUER"       "${OKTA_ISSUER:-}"
inject "OKTA_CLIENT_ID"    "${OKTA_CLIENT_ID:-}"
inject "OKTA_REDIRECT_URI" "${OKTA_REDIRECT_URI:-}"
inject "OKTA_SCOPES"       "${OKTA_SCOPES:-}"

exit 0
