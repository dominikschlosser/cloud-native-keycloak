#!/usr/bin/env bash
# Deploys Keycloak 26.7.0 + k8store (config in Kubernetes CRs) + PostgreSQL (users,
# sessions) into the shared kind cluster, namespace kc-03.
#
# Usage: scenarios/02-k8store-postgres/deploy.sh [--preconfigured] [--build]
#   (no flag)        fresh instance in write mode (master realm only, click-config)
#   --preconfigured  applies the version-controlled demo realm CRs, then read-only mode
#   --build          force re-stage the provider jars before building the image
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

NS=kc-03
IMAGE="${CNK_REGISTRY}/cnk-03:dev"
K8STORE_VERSION=0.1.5
JAR="target/providers/keycloak-k8store-${K8STORE_VERSION}.jar"
CRDS_URL="https://github.com/dominikschlosser/keycloak-k8store/releases/download/v${K8STORE_VERSION}/keycloak-k8store-crds.yaml"

PRECONFIGURED=false
BUILD=false
while [ $# -gt 0 ]; do
  case "$1" in
    --preconfigured) PRECONFIGURED=true; shift ;;
    --build) BUILD=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

require_cluster

if [ "${BUILD}" = true ] || [ ! -f "${JAR}" ]; then
  log "Staging k8store provider jars"
  ./build-providers.sh
fi

log "Building and pushing ${IMAGE}"
docker build -q -f Dockerfile -t "${IMAGE}" . >/dev/null
docker push -q "${IMAGE}"

${KUBECTL} get ns "${NS}" >/dev/null 2>&1 || ${KUBECTL} create ns "${NS}"
log "Applying k8store CRDs (published bundle, ${K8STORE_VERSION})"
${KUBECTL} apply --server-side -f "${CRDS_URL}" >/dev/null
log "Applying RBAC and PostgreSQL"
${KUBECTL} apply -f manifests/00-rbac.yaml
apply_db "${NS}" postgres

if [ "${PRECONFIGURED}" = true ]; then
  # GitOps: all config (master + demo realms) is applied as CRs up front and Keycloak boots
  # read-only from the start, so the CRs are the single source of truth. The admin user is
  # seeded by the Job (KC_BOOTSTRAP_ADMIN does not fire when master already exists).
  READ_ONLY=true
  log "Applying version-controlled CRs (master + demo realms)"
  ${KUBECTL} -n "${NS}" apply -f config/
else
  # Empty instance: boot writable so Keycloak bootstraps the master realm and the admin.
  READ_ONLY=false
fi

${KUBECTL} apply -f manifests/10-keycloak.yaml
${KUBECTL} -n "${NS}" set env deployment/keycloak "KC_SPI_DATASTORE__K8STORE__READ_ONLY=${READ_ONLY}"
${KUBECTL} -n "${NS}" rollout restart deployment/keycloak
wait_rollout "${NS}" deployment/postgres 300s
wait_rollout "${NS}" deployment/keycloak 600s

if [ "${PRECONFIGURED}" = true ]; then
  log "Seeding admin user for the pre-existing master realm"
  ${KUBECTL} -n "${NS}" delete job/bootstrap-admin --ignore-not-found >/dev/null 2>&1 || true
  ${KUBECTL} apply -f manifests/bootstrap-admin-job.yaml
  ${KUBECTL} -n "${NS}" wait --for=condition=complete job/bootstrap-admin --timeout=180s
fi

${KUBECTL} -n "${NS}" get pods -o wide
cat <<EOF

Deployed scenario 03 (k8store + PostgreSQL) into namespace ${NS}.
  Verify:  test/verify.sh ${NS} $([ "${PRECONFIGURED}" = true ] && echo 'demo demo-app' || echo 'master security-admin-console')
  Console: http://localhost:8080  (admin/admin), management http://localhost:9000
  Config:  kubectl -n ${NS} get keycloakrealms,keycloakclients
EOF
