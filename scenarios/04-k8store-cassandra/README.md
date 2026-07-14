# Scenario 4 — k8store (config in CRs) + Cassandra (dynamic)

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

### The Cassandra driver reference.conf

As in [scenario 6](../06-filestore-cassandra), the shaded cassandra jar overwrites the driver's
`reference.conf`, so `build-providers.sh` stages the driver's real one and the deployment supplies it
with `-Dconfig.file=/opt/keycloak/conf/cassandra-driver.conf`.

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

The same k8store CR set as [scenario 3](../03-k8store-postgres) (the `demo` realm plus the master-side
management client and roles needed to administer it). `deploy.sh --preconfigured` applies `config/`
and switches to read-only mode so the CRs are the single source of truth. Editing a CR and
`kubectl apply`-ing it updates every replica within milliseconds, no restart.
