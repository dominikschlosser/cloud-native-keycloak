#!/usr/bin/env bash
# Stages the k8store provider jars (plus its fabric8 runtime dependencies) into
# target/providers/. Run before building the image (deploy.sh does this automatically).
# The CRDs are applied from the published bundle by deploy.sh, not extracted here.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

K8STORE_VERSION="${K8STORE_VERSION:-0.1.5}"

resolve_providers target/providers \
  "io.github.dominikschlosser:keycloak-k8store:${K8STORE_VERSION}"
