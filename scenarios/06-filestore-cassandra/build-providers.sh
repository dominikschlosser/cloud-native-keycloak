#!/usr/bin/env bash
# Stages the filestore + cassandra provider jars into target/providers/. filestore serves
# the config areas, cassandra serves the dynamic areas (users, sessions), so this runs
# fully database-free. The cassandra jar is shaded; filestore needs commons-text, and the
# jars Keycloak already ships are pruned to avoid classpath conflicts.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

FILESTORE_VERSION="${FILESTORE_VERSION:-3.0.0}"
CASSANDRA_VERSION="${CASSANDRA_VERSION:-6.0.0}"

resolve_providers target/providers \
  "de.arbeitsagentur.opdt:keycloak-extension-filestore:${FILESTORE_VERSION}" \
  "de.arbeitsagentur.opdt:keycloak-cassandra-extension:${CASSANDRA_VERSION}"

( cd target/providers && rm -f \
    jboss-logmanager-*.jar log4j-jboss-logmanager-*.jar \
    wildfly-common-*.jar commons-lang3-*.jar )
log "Providers after prune: $(ls -1 target/providers)"

# The shaded extension jar drops the Cassandra driver own reference.conf (its advanced.*
# defaults), so stage an application.conf that carries them (loaded via -Dconfig.file).
cp ../../lib/cassandra-application.conf target/cassandra-application.conf
