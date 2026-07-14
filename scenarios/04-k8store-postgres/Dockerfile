# Bakes the k8store provider into a pre-built (--optimized) Keycloak 26.7.0 image.
# Provider jars are staged into target/providers/ by build-providers.sh first.
FROM quay.io/keycloak/keycloak:26.7.0 AS builder

COPY target/providers/*.jar /opt/keycloak/providers/

# Selecting the k8store datastore is the opt-in. It self-configures from there
# (disables the JPA realm provider and the realm/authz/org caches). Organizations stay
# off because the default areas keep groups in CRs and the JPA organization store cannot
# reference them (enable the organization area to use it).
RUN /opt/keycloak/bin/kc.sh build \
      --features=stateless \
      --db=postgres \
      --spi-datastore--provider=k8store \
      --features-disabled=organization \
      --health-enabled=true \
      --metrics-enabled=true

FROM quay.io/keycloak/keycloak:26.7.0
COPY --from=builder /opt/keycloak/ /opt/keycloak/
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
