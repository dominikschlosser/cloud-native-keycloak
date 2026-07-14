#!/usr/bin/env bash
# Stages the k8store + cassandra provider jars into target/providers/ and extracts the CRD
# manifests from the k8store jar into crds/. k8store serves the config areas (as CRs),
# cassandra serves the dynamic areas (users, sessions), so this runs database-free.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

K8STORE_VERSION="${K8STORE_VERSION:-0.1.3}"
CASSANDRA_VERSION="${CASSANDRA_VERSION:-6.0.0}"

resolve_providers target/providers \
  "io.github.dominikschlosser:keycloak-k8store:${K8STORE_VERSION}" \
  "de.arbeitsagentur.opdt:keycloak-cassandra-extension:${CASSANDRA_VERSION}"

extract_k8store_crds \
  "target/providers/keycloak-k8store-${K8STORE_VERSION}.jar" crds

# The shaded extension jar overwrites the Cassandra driver's own reference.conf, so its
# defaults (advanced.*) are missing at runtime. Stage the driver's reference.conf so the
# image can supply it via -Dconfig.file.
cp ../../lib/cassandra-driver.conf target/cassandra-driver.conf
