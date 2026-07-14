#!/usr/bin/env bash
# Measures request availability while Keycloak pods are replaced (a rolling update, the
# same pod-replacement a version upgrade performs). Drives load from INSIDE the cluster (so
# kube-proxy load-balances across the Service's ready endpoints, unlike a port-forward which
# pins to one pod), triggers a rollout restart, and reports how many requests failed.
#
# Usage: test/rollout-availability.sh <namespace> [deployment/keycloak] [svc]
set -euo pipefail
cd "$(dirname "$0")"
source ../lib/common.sh

NS="${1:?namespace required}"
OBJ="${2:-deployment/keycloak}"
SVC="${3:-keycloak}"
POD=cnk-load

${KUBECTL} -n "${NS}" delete pod "${POD}" --ignore-not-found >/dev/null 2>&1 || true
log "Starting in-cluster load generator against http://${SVC}:8080"
${KUBECTL} -n "${NS}" run "${POD}" --image=curlimages/curl:8.11.1 --restart=Never --command -- \
  sh -c "i=0; while [ \$i -lt 500 ]; do curl -s -o /dev/null -w '%{http_code}\n' --max-time 3 http://${SVC}:8080/realms/master; i=\$((i+1)); sleep 0.2; done" >/dev/null
${KUBECTL} -n "${NS}" wait --for=condition=Ready "pod/${POD}" --timeout=60s >/dev/null
sleep 3

log "Load running, triggering rollout restart of ${OBJ}"
${KUBECTL} -n "${NS}" rollout restart "${OBJ}"
${KUBECTL} -n "${NS}" rollout status "${OBJ}" --timeout=600s
log "Rollout complete, sampling a few more seconds then stopping load"
sleep 3

LOGS=$(${KUBECTL} -n "${NS}" logs "${POD}" 2>/dev/null || true)
${KUBECTL} -n "${NS}" delete pod "${POD}" --ignore-not-found >/dev/null 2>&1 || true

total=$(printf '%s\n' "${LOGS}" | grep -cE '^[0-9]{3}$' || true)
ok=$(printf '%s\n' "${LOGS}" | grep -c '^200$' || true)
fail=$((total - ok))
log "Availability during rollout: ${ok}/${total} returned 200, ${fail} failed"
if [ "${fail}" -gt 0 ]; then
  printf '%s\n' "${LOGS}" | grep -vE '^200$' | grep -E '^[0-9]{3}$' | sort | uniq -c | sed 's/^/  non-200: /'
fi
