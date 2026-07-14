#!/usr/bin/env bash
# Stands up a real GitOps demo on the shared kind cluster. It installs ArgoCD and a small
# in-cluster git server (seeded with argocd/app/), then creates an ArgoCD Application that
# syncs the k8store + PostgreSQL Keycloak setup from that git repo. Keycloak boots read-only,
# so the committed CRs are the source of truth. A PostSync hook Job seeds the admin user.
#
# This uses the k8store + PostgreSQL setup (scenario 3) as the example. The Keycloak image is
# scenario 3's, so it is built here if missing (CI builds it in a real setup, where ArgoCD only
# syncs manifests, not images).
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh

require_cluster
KC_IMAGE="${CNK_REGISTRY}/cnk-03:dev"
GIT_IMAGE="${CNK_REGISTRY}/cnk-git-server:dev"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"

# 1. Keycloak image (scenario 3's). Build if absent.
if ! docker image inspect "${KC_IMAGE}" >/dev/null 2>&1; then
  log "Building the Keycloak image (scenario 3)"
  ( cd scenarios/03-k8store-postgres && ./build-providers.sh && docker build -q -t "${KC_IMAGE}" . )
fi
docker push -q "${KC_IMAGE}" >/dev/null

# 2. In-cluster git server image, seeded with argocd/app/
log "Building and pushing the in-cluster git server (seeded with argocd/app/)"
docker build -q -f argocd/git-server/Dockerfile -t "${GIT_IMAGE}" argocd/ >/dev/null
docker push -q "${GIT_IMAGE}" >/dev/null

# 3. ArgoCD (server-side apply, because some CRDs are too large for client-side)
${KUBECTL} get ns argocd >/dev/null 2>&1 || ${KUBECTL} create ns argocd
log "Installing ArgoCD (${ARGOCD_VERSION})"
${KUBECTL} apply --server-side --force-conflicts -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" >/dev/null

# 4. Git server + k8store CRDs
${KUBECTL} apply -f argocd/git-server/git-server.yaml >/dev/null
${KUBECTL} apply --server-side -f \
  "https://github.com/dominikschlosser/keycloak-k8store/releases/download/v0.1.5/keycloak-k8store-crds.yaml" >/dev/null

log "Waiting for ArgoCD and the git server"
wait_rollout argocd deployment/argocd-repo-server 300s
wait_rollout argocd deployment/argocd-server 300s
wait_rollout argocd deployment/git-server 120s

# 5. The Application (ArgoCD syncs from git://git-server:9418/repo)
log "Creating the ArgoCD Application"
${KUBECTL} apply -f argocd/application.yaml >/dev/null
${KUBECTL} -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/keycloak-k8store --timeout=400s
# The admin is seeded by a PostSync hook, so wait for the whole sync operation (hooks
# included) to finish before reporting ready.
${KUBECTL} -n argocd wait --for=jsonpath='{.status.operationState.phase}'=Succeeded \
  application/keycloak-k8store --timeout=180s

${KUBECTL} -n argocd get application keycloak-k8store
${KUBECTL} -n kc-argocd get pods -o wide
cat <<'EOF'

ArgoCD deployed Keycloak + CRs from the in-cluster git repo (read-only).
  Verify:  CNK_KC_SVC=keycloak test/verify.sh kc-argocd demo demo-app
  Console: http://localhost:8080  (admin/admin)
  ArgoCD:  kubectl -n argocd port-forward svc/argocd-server 8081:443
           (user admin, password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
  Change config the GitOps way: edit argocd/app/config/*.yaml, rebuild+push the git-server
  image (or push to the repo), and ArgoCD reconciles it.
  Tear down: argocd/teardown.sh
EOF
