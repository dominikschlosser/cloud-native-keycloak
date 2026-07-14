#!/usr/bin/env bash
# Stages the k8store provider jars (plus its fabric8 runtime dependencies) into
# target/providers/ and extracts the CRD manifests from the jar into crds/.
# Run before building the image (deploy.sh does this automatically).
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

K8STORE_VERSION="${K8STORE_VERSION:-0.1.3}"

resolve_providers target/providers \
  "io.github.dominikschlosser:keycloak-k8store:${K8STORE_VERSION}"

extract_k8store_crds \
  "target/providers/keycloak-k8store-${K8STORE_VERSION}.jar" crds
