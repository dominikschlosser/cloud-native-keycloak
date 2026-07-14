# Bakes k8store + cassandra providers into a pre-built Keycloak 26.7.0 image. k8store serves
# the config areas (as Kubernetes CRs), cassandra serves the dynamic areas, so there is no
# relational database. Provider jars are staged into target/providers/ by build-providers.sh.
FROM quay.io/keycloak/keycloak:26.7.0 AS builder

COPY target/providers/*.jar /opt/keycloak/providers/

# k8store is the selected datastore (config areas). cassandra claims the dynamic areas via
# its areas option. jpa-legacy is off because nothing uses a relational database.
RUN /opt/keycloak/bin/kc.sh build \
      --features=stateless \
      --spi-datastore--provider=k8store \
      --spi-datastore--cassandra--areas=user,user-session,auth-session,login-failure,single-use-object,revoked-token \
      --features-disabled=organization \
      --spi-connections-jpa-legacy-enabled=false \
      --db=dev-mem \
      --health-enabled=true \
      --metrics-enabled=true

FROM quay.io/keycloak/keycloak:26.7.0
COPY --from=builder /opt/keycloak/ /opt/keycloak/
# Cassandra driver defaults (see build-providers.sh), supplied at runtime via -Dconfig.file.
COPY target/cassandra-application.conf /opt/keycloak/conf/cassandra-application.conf
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
