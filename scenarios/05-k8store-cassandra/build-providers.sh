#!/usr/bin/env bash
# Stages the k8store + cassandra provider jars into target/providers/. k8store serves the
# config areas (as CRs), cassandra serves the dynamic areas (users, sessions), so this runs
# database-free. The CRDs are applied from the published bundle by deploy.sh.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

K8STORE_VERSION="${K8STORE_VERSION:-0.1.5}"
CASSANDRA_VERSION="${CASSANDRA_VERSION:-6.0.0}"

resolve_providers target/providers \
  "io.github.dominikschlosser:keycloak-k8store:${K8STORE_VERSION}" \
  "de.arbeitsagentur.opdt:keycloak-cassandra-extension:${CASSANDRA_VERSION}"

# The shaded extension jar drops the Cassandra driver own reference.conf (its advanced.*
# defaults), so stage an application.conf that carries them (loaded via -Dconfig.file).
cp ../../lib/cassandra-application.conf target/cassandra-application.conf
