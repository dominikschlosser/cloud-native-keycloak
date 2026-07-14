#!/usr/bin/env bash
# Deploys stock Keycloak 26.7.0 + PostgreSQL into the shared kind cluster (namespace kc-03),
# with configuration managed by keycloak-config-cli.
#
# Usage: scenarios/03-keycloak-config-cli/deploy.sh [--preconfigured]
#   (no flag)        fresh Keycloak (master realm only)
#   --preconfigured  runs keycloak-config-cli (config/demo-realm.yaml) via a Job to import the
#                    demo realm
#
# No custom image (stock Keycloak). Config lives in config/*.yaml and is imported through the
# admin API by a one-shot keycloak-config-cli Job.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

NS=kc-03
PRECONFIGURED=false
while [ $# -gt 0 ]; do
  case "$1" in
    --preconfigured) PRECONFIGURED=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

require_cluster

${KUBECTL} get ns "${NS}" >/dev/null 2>&1 || ${KUBECTL} create ns "${NS}"
log "Applying PostgreSQL and Keycloak"
apply_db "${NS}" postgres
${KUBECTL} apply -f manifests/10-keycloak.yaml
wait_rollout "${NS}" deployment/postgres 300s
wait_rollout "${NS}" deployment/keycloak 600s

if [ "${PRECONFIGURED}" = true ]; then
  log "Importing the demo realm with keycloak-config-cli"
  ${KUBECTL} -n "${NS}" delete configmap keycloak-config --ignore-not-found >/dev/null 2>&1 || true
  ${KUBECTL} -n "${NS}" create configmap keycloak-config --from-file=config/
  ${KUBECTL} -n "${NS}" delete job/config-cli --ignore-not-found >/dev/null 2>&1 || true
  ${KUBECTL} apply -f manifests/config-cli-job.yaml
  ${KUBECTL} -n "${NS}" wait --for=condition=complete job/config-cli --timeout=300s
fi

${KUBECTL} -n "${NS}" get pods -o wide
cat <<EOF

Deployed scenario 03 (keycloak-config-cli + PostgreSQL) into namespace ${NS}.
  Verify:  test/verify.sh ${NS} $([ "${PRECONFIGURED}" = true ] && echo 'demo demo-app' || echo 'master security-admin-console')
  Console: http://localhost:8080  (admin/admin), management http://localhost:9000
EOF
