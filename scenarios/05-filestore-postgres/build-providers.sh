#!/usr/bin/env bash
# Stages the filestore provider jar (plus commons-text, which it needs for env-var
# substitution) into target/providers/. Keycloak already ships commons-lang3 and the
# jboss logging jars, so those duplicates are pruned to avoid classpath conflicts.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

FILESTORE_VERSION="${FILESTORE_VERSION:-3.0.0}"

resolve_providers target/providers \
  "de.arbeitsagentur.opdt:keycloak-extension-filestore:${FILESTORE_VERSION}"

# Drop the jars that the Keycloak 26.7.0 image already provides (keeping an older copy
# here would shadow them).
( cd target/providers && rm -f \
    jboss-logmanager-*.jar log4j-jboss-logmanager-*.jar \
    wildfly-common-*.jar commons-lang3-*.jar )
log "Providers after prune: $(ls -1 target/providers)"
