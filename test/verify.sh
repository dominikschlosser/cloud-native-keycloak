#!/usr/bin/env bash
# End-to-end verification for a deployed scenario.
# Opens a temporary port-forward to the scenario's Keycloak Service, runs the REST
# smoke check, then a real browser login that loads the Clients overview.
#
# Usage: test/verify.sh <namespace> [realm] [expect-client]
#   namespace      the scenario namespace (e.g. kc-02)
#   realm          realm whose Clients page is checked (default master)
#   expect-client  client id that must appear (default security-admin-console)
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh

NS="${1:?namespace required}"
REALM="${2:-master}"
EXPECT_CLIENT="${3:-security-admin-console}"
PORT="${CNK_VERIFY_PORT:-18080}"
SVC="${CNK_KC_SVC:-keycloak}"
BASE="http://localhost:${PORT}"
CHROME="${CHROME_PATH:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

require_cluster

log "Port-forwarding svc/${SVC} in ${NS} to localhost:${PORT}"
${KUBECTL} -n "${NS}" port-forward "svc/${SVC}" "${PORT}:8080" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "${PF_PID}" 2>/dev/null || true' EXIT
sleep 3

rest_smoke "${BASE}"

if [ ! -d test/node_modules/puppeteer-core ]; then
  log "Installing puppeteer-core (first run only)"
  (cd test && npm install --silent --no-fund --no-audit)
fi

mkdir -p test/screenshots
log "Browser verify: login admin/admin, open ${REALM} Clients, expect '${EXPECT_CLIENT}'"
BASE_URL="${BASE}" REALM="${REALM}" EXPECT_CLIENT="${EXPECT_CLIENT}" \
  CHROME_PATH="${CHROME}" SHOT="test/screenshots/${NS}-${REALM}.png" \
  node test/verify-login.mjs

log "Verification PASSED for ${NS} (${REALM})"
