# Bakes the filestore provider into a pre-built (--optimized) Keycloak 26.7.0 image.
# Provider jars are staged into target/providers/ by build-providers.sh first.
# The committed demo config in config/filestore/ is baked in as a read-only seed that the
# pre-configured variant serves (config/filestore/ is empty for a plain build).
FROM quay.io/keycloak/keycloak:26.7.0 AS builder

COPY target/providers/*.jar /opt/keycloak/providers/

RUN /opt/keycloak/bin/kc.sh build \
      --features=stateless \
      --db=postgres \
      --spi-datastore--provider=file \
      --features-disabled=authorization,admin-fine-grained-authz,organization \
      --health-enabled=true \
      --metrics-enabled=true

FROM quay.io/keycloak/keycloak:26.7.0
COPY --from=builder /opt/keycloak/ /opt/keycloak/
COPY config/filestore/ /opt/keycloak/seed/filestore/
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
