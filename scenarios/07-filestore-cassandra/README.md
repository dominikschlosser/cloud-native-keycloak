# Scenario 7: filestore (config in YAML files) + Cassandra (dynamic)

Keycloak 26.7.0 running **fully database-free**:
[filestore](https://github.com/dominikschlosser/keycloak-extension-filestore) serves the
configuration entities from YAML files, and the
[keycloak-cassandra-extension](https://github.com/opdt/keycloak-cassandra-extension) serves the
dynamic areas (users, sessions) from Apache Cassandra.

## How it works

The image (`Dockerfile`) bakes both provider jars and runs `kc.sh build`:

```
--features=stateless --spi-datastore--provider=file \
--spi-datastore--cassandra--areas=user,user-session,auth-session,login-failure,single-use-object,revoked-token \
--features-disabled=authorization,admin-fine-grained-authz,organization \
--spi-connections-jpa-legacy-enabled=false --db=dev-mem
```

`file` is the selected datastore, so it serves the config areas. The cassandra extension claims the
listed dynamic areas through its `areas` option, so users and sessions go to Cassandra. Nothing uses
a relational database, so JPA legacy is turned off. This is the composition the filestore extension
documents.

Cassandra connection settings are passed as `KC_SPI_CASSANDRA_CONNECTION_DEFAULT_*` env vars.
`KC_SPI_DATASTORE__FILE__RESOURCES_VERSION_SEED` pins the theme resources tag (required without a
database, see [scenario 6](../06-filestore-postgres)).

### Cassandra driver config

`lib/cassandra-application.conf` holds the Cassandra driver configuration. It is baked into the image
and loaded with `-Dconfig.file`. Edit it for driver tuning (consistency, timeouts).

## Two variants, two topologies

Like [scenario 6](../06-filestore-postgres), filestore config is per-pod:

- **new**: one replica, writable filestore on a PVC, `KC_BOOTSTRAP_ADMIN` seeds the admin (in
  Cassandra).
- **--preconfigured**: the committed `config/filestore/` is baked into the image as a read-only
  seed, two replicas. Because the seed already contains the master realm, a one-shot Job runs
  `kc.sh bootstrap-admin` to seed the admin into Cassandra. The seed disables the `VERIFY_PROFILE`
  required action so that admin (which has no email) can log in.

## Organizations

**Disabled.** Neither filestore nor the cassandra extension supports Organizations. Only
[scenario 1](../01-operator-stateless) enables them.

## Deploy

```bash
../../kind/kind-up.sh            # once, shared across all scenarios

./deploy.sh                      # new instance: 1 replica, writable PVC, master realm only
./deploy.sh --preconfigured      # GitOps instance: demo realm from the baked seed, 2 replicas
```

Cassandra takes ~60-90s to become ready, so the first deploy is slower than the others.

### Verify

```bash
../../test/verify.sh kc-07 master security-admin-console   # new instance
../../test/verify.sh kc-07 demo   demo-app                 # pre-configured instance
```

## The version-controlled config (`config/filestore/`)

The same demo config as [scenario 6](../06-filestore-postgres) (the `master` and `demo` realms as
YAML files), bootstrapped in write mode and committed. Editing a file and rebuilding the image
republishes the config.
