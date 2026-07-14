#!/usr/bin/env bash
# Deploys standard Keycloak 26.7.0 managed by the Keycloak Operator, with the stateless
# feature and PostgreSQL, into the shared kind cluster, namespace kc-01.
#
# Usage: scenarios/01-operator-stateless/deploy.sh [--preconfigured]
#   (no flag)        fresh instance managed by the operator (master realm only)
#   --preconfigured  additionally imports the version-controlled demo realm (with an
#                    Organization, which only this scenario supports)
#
# This scenario uses no custom image. Config is version-controlled as a KeycloakRealmImport
# CR and materialized by the operator's import Job.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

NS=kc-01
PRECONFIGURED=false
while [ $# -gt 0 ]; do
  case "$1" in
    --preconfigured) PRECONFIGURED=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

require_cluster

${KUBECTL} get ns "${NS}" >/dev/null 2>&1 || ${KUBECTL} create ns "${NS}"

# Operator CRDs and deployment come straight from the pinned upstream release.
OPERATOR_VERSION="${OPERATOR_VERSION:-26.7.0}"
OPERATOR_BASE="https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${OPERATOR_VERSION}/kubernetes"
log "Installing the Keycloak Operator (${OPERATOR_VERSION}) and its CRDs from upstream"
for crd in keycloaks keycloakrealmimports keycloakoidcclients keycloaksamlclients; do
  ${KUBECTL} apply --server-side -f "${OPERATOR_BASE}/${crd}.k8s.keycloak.org-v1.yml" >/dev/null
done
${KUBECTL} -n "${NS}" apply -f "${OPERATOR_BASE}/kubernetes.yml"
wait_rollout "${NS}" deployment/keycloak-operator 300s

log "Applying secrets, PostgreSQL and the Keycloak CR"
${KUBECTL} apply -f manifests/00-secrets.yaml
apply_db "${NS}" postgres
wait_rollout "${NS}" deployment/postgres 300s
${KUBECTL} apply -f manifests/10-keycloak.yaml

log "Waiting for the operator to roll out Keycloak (StatefulSet keycloak)"
${KUBECTL} -n "${NS}" wait --for=condition=Ready keycloak/keycloak --timeout=600s

if [ "${PRECONFIGURED}" = true ]; then
  log "Importing the version-controlled demo realm"
  ${KUBECTL} apply -f config/realm-demo.yaml
  ${KUBECTL} -n "${NS}" wait --for=condition=Done keycloakrealmimport/demo --timeout=300s
fi

${KUBECTL} -n "${NS}" get pods -o wide
cat <<EOF

Deployed scenario 01 (operator + stateless + PostgreSQL) into namespace ${NS}.
  Verify:  CNK_KC_SVC=keycloak-service test/verify.sh ${NS} $([ "${PRECONFIGURED}" = true ] && echo 'demo demo-app' || echo 'master security-admin-console')
  Console: kubectl -n ${NS} port-forward svc/keycloak-service 8080:8080  (admin/admin)
EOF
