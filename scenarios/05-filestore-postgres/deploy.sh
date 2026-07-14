#!/usr/bin/env bash
# Deploys Keycloak 26.7.0 + filestore (config in YAML files) + PostgreSQL (users,
# sessions) into the shared kind cluster, namespace kc-05.
#
# Usage: scenarios/04-filestore-postgres/deploy.sh [--preconfigured] [--build]
#   (no flag)        fresh single-replica instance, writable filestore on a PVC
#   --preconfigured  serves the committed config/filestore/ demo realm (baked into the
#                    image, read-only), two replicas
#   --build          force re-stage the provider jars before building the image
#
# filestore config is per-pod (not shared through an API like k8store CRs). The writable
# instance therefore runs one replica on a persistent volume. The pre-configured instance
# bakes an identical read-only seed into the image and runs two.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

NS=kc-05
IMAGE="${CNK_REGISTRY}/cnk-05:dev"
JAR=target/providers/keycloak-extension-filestore-3.0.0.jar

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
  log "Staging filestore provider jars"
  ./build-providers.sh
fi

log "Building and pushing ${IMAGE}"
docker build -q -f Dockerfile -t "${IMAGE}" . >/dev/null
docker push -q "${IMAGE}"

${KUBECTL} get ns "${NS}" >/dev/null 2>&1 || ${KUBECTL} create ns "${NS}"
log "Applying PostgreSQL and Keycloak"
apply_db "${NS}" postgres
${KUBECTL} apply -f manifests/service.yaml
if [ "${PRECONFIGURED}" = true ]; then
  # Drop the writable deployment and its PVC when switching a namespace from new to
  # pre-configured (the pre-configured deployment has no volume and a different strategy).
  ${KUBECTL} -n "${NS}" delete deployment/keycloak --ignore-not-found >/dev/null 2>&1 || true
  ${KUBECTL} -n "${NS}" delete pvc/filestore --ignore-not-found >/dev/null 2>&1 || true
  ${KUBECTL} apply -f manifests/keycloak-preconfigured.yaml
else
  ${KUBECTL} apply -f manifests/keycloak-new.yaml
fi
${KUBECTL} -n "${NS}" rollout restart deployment/keycloak
wait_rollout "${NS}" deployment/postgres 300s
wait_rollout "${NS}" deployment/keycloak 600s

if [ "${PRECONFIGURED}" = true ]; then
  # The seed carries the master realm, so no admin user is bootstrapped automatically.
  # Seed one into the database for the pre-existing realm.
  log "Seeding admin user for the pre-existing master realm"
  ${KUBECTL} -n "${NS}" delete job/bootstrap-admin --ignore-not-found >/dev/null 2>&1 || true
  ${KUBECTL} apply -f manifests/bootstrap-admin-job.yaml
  ${KUBECTL} -n "${NS}" wait --for=condition=complete job/bootstrap-admin --timeout=180s
fi

${KUBECTL} -n "${NS}" get pods -o wide
cat <<EOF

Deployed scenario 05 (filestore + PostgreSQL) into namespace ${NS}.
  Verify:  test/verify.sh ${NS} $([ "${PRECONFIGURED}" = true ] && echo 'demo demo-app' || echo 'master security-admin-console')
  Console: kubectl -n ${NS} port-forward svc/keycloak 8080:8080  (admin/admin)
EOF
