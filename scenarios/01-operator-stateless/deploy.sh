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
# CR (realm, Admin API v1) and a KeycloakOIDCClient CR (a client, Admin API v2), both
# reconciled by the operator.
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
# NodePort Service selecting the operator-managed pods, for http://localhost:8080 access.
${KUBECTL} apply -f manifests/20-keycloak-nodeport.yaml

log "Waiting for the operator to roll out Keycloak (StatefulSet keycloak)"
${KUBECTL} -n "${NS}" wait --for=condition=Ready keycloak/keycloak --timeout=600s

if [ "${PRECONFIGURED}" = true ]; then
  log "Importing the version-controlled demo realm (KeycloakRealmImport, Admin API v1)"
  ${KUBECTL} apply -f config/realm-demo.yaml
  ${KUBECTL} -n "${NS}" wait --for=condition=Done keycloakrealmimport/demo --timeout=300s
  log "Managing a client declaratively (KeycloakOIDCClient, Admin API v2)"
  ${KUBECTL} apply -f config/client-demo-oidc.yaml
  # The KeycloakOIDCClient reports a HasErrors condition (not Ready). Poll until it reconciles clean.
  status=""
  for _ in $(seq 1 36); do
    status=$(${KUBECTL} -n "${NS}" get keycloakoidcclient/demo-oidc-app \
      -o jsonpath='{.status.conditions[?(@.type=="HasErrors")].status}' 2>/dev/null || true)
    [ "${status}" = "False" ] && break
    sleep 5
  done
  [ "${status}" = "False" ] || die "KeycloakOIDCClient demo-oidc-app did not reconcile: $(${KUBECTL} -n "${NS}" get keycloakoidcclient/demo-oidc-app -o jsonpath='{.status.conditions[?(@.type=="HasErrors")].message}')"
fi

${KUBECTL} -n "${NS}" get pods -o wide
cat <<EOF

Deployed scenario 01 (operator + stateless + PostgreSQL) into namespace ${NS}.
  Verify:  test/verify.sh ${NS} $([ "${PRECONFIGURED}" = true ] && echo 'demo demo-app' || echo 'master security-admin-console')
  Console: http://localhost:8080  (admin/admin), management http://localhost:9000
EOF
