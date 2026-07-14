# Scenario 4: k8store (config in CRs) + Cassandra (dynamic)

Keycloak 26.7.0 running **fully database-free**:
[k8store](https://github.com/dominikschlosser/keycloak-k8store) serves the configuration entities as
Kubernetes Custom Resources, and the
[keycloak-cassandra-extension](https://github.com/opdt/keycloak-cassandra-extension) serves the
dynamic areas (users, sessions) from Apache Cassandra. It is the most experimental combination here.

## How it works

The image (`Dockerfile`) bakes both provider jars and runs `kc.sh build`:

```
--features=stateless --spi-datastore--provider=k8store \
--spi-datastore--cassandra--areas=user,user-session,auth-session,login-failure,single-use-object,revoked-token \
--features-disabled=organization \
--spi-connections-jpa-legacy-enabled=false --db=dev-mem
```

`k8store` is the selected datastore, so it serves the config areas as CRs (same GitOps model as
[scenario 3](../03-k8store-postgres)). The cassandra extension claims the listed dynamic areas
through its `areas` option, so users and sessions go to Cassandra instead of the relational database
k8store would otherwise use. Nothing uses JPA, so JPA legacy is turned off.

### Cassandra driver config

`lib/cassandra-application.conf` holds the Cassandra driver configuration. It is baked into the image
and loaded with `-Dconfig.file`. Edit it for driver tuning (consistency, timeouts).

## Organizations

**Disabled.** With the k8store default areas groups are CR-backed (the JPA organization store cannot
reference them), and the cassandra extension does not support Organizations either. Only
[scenario 1](../01-operator-stateless) enables them.

## Deploy

```bash
../../kind/kind-up.sh            # once, shared across all scenarios

./deploy.sh                      # new instance: write mode, master realm only
./deploy.sh --preconfigured      # GitOps instance: demo realm from config/, then read-only
```

Cassandra takes ~60-90s to become ready, so the first deploy is slower than the others.

### Verify

```bash
../../test/verify.sh kc-04 master security-admin-console   # new instance
../../test/verify.sh kc-04 demo   demo-app                 # pre-configured instance
```

## The version-controlled config (`config/`)

The same full-realm k8store CR set as [scenario 3](../03-k8store-postgres) (`master` and `demo`
realms). Same two variants: **new** boots writable and `KC_BOOTSTRAP_ADMIN` seeds the admin;
**--preconfigured** applies all CRs up front, boots **read-only from the start**, and a one-shot
`bootstrap-admin` Job seeds the admin into Cassandra. Editing a CR and `kubectl apply`-ing it updates
every replica within milliseconds, no restart.
