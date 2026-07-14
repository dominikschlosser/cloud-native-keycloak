#!/usr/bin/env bash
# Creates (idempotently) the shared local test infrastructure for all scenarios:
#   - a docker registry container `cnk-registry` on localhost:5001
#   - a kind cluster `cnk` with 1 control-plane and 2 worker nodes, wired to the
#     local registry (the standard kind local-registry pattern).
#
# The two worker nodes are load-bearing: the Keycloak Deployments in scenarios 2-5
# run 2 replicas pinned onto distinct workers via required podAntiAffinity, which is
# how cross-replica config consistency gets exercised.
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER_NAME=cnk
REG_NAME=cnk-registry
REG_PORT=5001

# 1. Local registry container
if [ "$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || true)" != 'true' ]; then
  docker rm -f "${REG_NAME}" 2>/dev/null || true
  docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" \
    --network bridge --name "${REG_NAME}" registry:2
  echo "Started local registry ${REG_NAME} on localhost:${REG_PORT}"
else
  echo "Local registry ${REG_NAME} already running"
fi

# 2. kind cluster: 1 control-plane + 2 workers
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "kind cluster ${CLUSTER_NAME} already exists"
else
  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
EOF
fi

# 3. Tell containerd on every node how to reach the registry as localhost:5001
REGISTRY_DIR="/etc/containerd/certs.d/localhost:${REG_PORT}"
for node in $(kind get nodes --name "${CLUSTER_NAME}"); do
  docker exec "${node}" mkdir -p "${REGISTRY_DIR}"
  cat <<EOF | docker exec -i "${node}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
[host."http://${REG_NAME}:5000"]
EOF
done

# 4. Connect the registry to the kind network so nodes can reach it
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${REG_NAME}")" = 'null' ]; then
  docker network connect "kind" "${REG_NAME}"
fi

# 5. Document the local registry for tooling
cat <<EOF | kubectl --context "kind-${CLUSTER_NAME}" apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

kubectl --context "kind-${CLUSTER_NAME}" get nodes
echo
echo "Cluster ${CLUSTER_NAME} is up. Next: scenarios/<n>/deploy.sh"
