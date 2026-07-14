# Bakes filestore + cassandra providers into a pre-built (--optimized) Keycloak 26.7.0 image.
# filestore serves the config areas, cassandra serves the dynamic areas, so there is no
# relational database. Provider jars are staged into target/providers/ by build-providers.sh.
FROM quay.io/keycloak/keycloak:26.7.0 AS builder

COPY target/providers/*.jar /opt/keycloak/providers/

# file is the selected datastore (config areas). cassandra claims the dynamic areas via its
# areas option. jpa-legacy is turned off because nothing uses a relational database.
RUN /opt/keycloak/bin/kc.sh build \
      --features=stateless \
      --spi-datastore--provider=file \
      --spi-datastore--cassandra--areas=user,user-session,auth-session,login-failure,single-use-object,revoked-token \
      --features-disabled=authorization,admin-fine-grained-authz,organization \
      --spi-connections-jpa-legacy-enabled=false \
      --db=dev-mem \
      --health-enabled=true \
      --metrics-enabled=true

FROM quay.io/keycloak/keycloak:26.7.0
COPY --from=builder /opt/keycloak/ /opt/keycloak/
COPY config/filestore/ /opt/keycloak/seed/filestore/
# Cassandra driver defaults (see build-providers.sh), supplied at runtime via -Dconfig.file.
COPY target/cassandra-application.conf /opt/keycloak/conf/cassandra-application.conf
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
