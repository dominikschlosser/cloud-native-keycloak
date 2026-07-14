#!/usr/bin/env bash
# Removes the ArgoCD demo (the Application, the synced app namespace, ArgoCD, the git server).
# Leaves the shared kind cluster and the k8store CRDs in place.
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh

${KUBECTL} -n argocd delete application keycloak-k8store --ignore-not-found >/dev/null 2>&1 || true
${KUBECTL} delete ns kc-argocd --ignore-not-found >/dev/null 2>&1 || true
${KUBECTL} delete ns argocd --ignore-not-found >/dev/null 2>&1 || true
echo "Removed the ArgoCD demo (Application, kc-argocd, argocd namespaces)."
