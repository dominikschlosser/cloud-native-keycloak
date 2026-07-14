#!/usr/bin/env bash
# Tears down the shared local test infrastructure created by kind/kind-up.sh.
set -euo pipefail

CLUSTER_NAME=cnk
REG_NAME=cnk-registry

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
else
  echo "kind cluster ${CLUSTER_NAME} does not exist"
fi

if docker inspect "${REG_NAME}" >/dev/null 2>&1; then
  docker rm -f "${REG_NAME}" >/dev/null
  echo "Removed registry container ${REG_NAME}"
else
  echo "Registry container ${REG_NAME} does not exist"
fi
