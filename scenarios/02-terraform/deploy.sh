#!/usr/bin/env bash
# Deploys stock Keycloak 26.7.0 + PostgreSQL into the shared kind cluster (namespace kc-02),
# with configuration managed by the keycloak/keycloak Terraform provider.
#
# Usage: scenarios/02-terraform/deploy.sh [--preconfigured]
#   (no flag)        fresh Keycloak (master realm only)
#   --preconfigured  runs `terraform apply` (config/main.tf) via an in-cluster Job to create
#                    the demo realm
#
# No custom image (stock Keycloak). Config lives in config/*.tf and is applied through the
# admin API by a one-shot Terraform Job.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

NS=kc-02
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
  log "Applying the version-controlled demo realm with Terraform"
  ${KUBECTL} -n "${NS}" delete configmap terraform-config --ignore-not-found >/dev/null 2>&1 || true
  ${KUBECTL} -n "${NS}" create configmap terraform-config --from-file=config/
  ${KUBECTL} -n "${NS}" delete job/terraform-apply --ignore-not-found >/dev/null 2>&1 || true
  ${KUBECTL} apply -f manifests/terraform-job.yaml
  ${KUBECTL} -n "${NS}" wait --for=condition=complete job/terraform-apply --timeout=300s
fi

${KUBECTL} -n "${NS}" get pods -o wide
cat <<EOF

Deployed scenario 02 (Terraform + PostgreSQL) into namespace ${NS}.
  Verify:  test/verify.sh ${NS} $([ "${PRECONFIGURED}" = true ] && echo 'demo demo-app' || echo 'master security-admin-console')
  Console: http://localhost:8080  (admin/admin), management http://localhost:9000
EOF
