# Scenario 3 — k8store (config in CRs) + PostgreSQL (dynamic)

Keycloak 26.7.0 with the [k8store](https://github.com/dominikschlosser/keycloak-k8store) datastore
extension. Configuration entities (realms, clients, client scopes, roles, groups, identity
providers) live as **Kubernetes Custom Resources**; users and sessions live in **PostgreSQL**. This
is the GitOps pattern: the CRs are your version-controlled source of truth and Keycloak serves them.

## How it works

The image (`Dockerfile`) bakes the k8store provider jars into Keycloak and runs `kc.sh build` with:

```
--features=stateless --db=postgres --spi-datastore--provider=k8store --features-disabled=organization
```

Selecting `k8store` as the datastore is the whole opt-in. k8store self-configures from there (it
disables the JPA realm provider and the realm/authz/organization Infinispan caches). Each pod keeps a
watch-synchronized in-memory mirror of the CRs, so reads never hit the API server and the two
replicas need no coordination. `KC_SPI_DATASTORE__K8STORE__READ_ONLY` toggles whether config writes
through Keycloak are allowed.

Config CRs use Keycloak's own representation JSON as their spec, served verbatim. RBAC in
`manifests/00-rbac.yaml` grants the Keycloak ServiceAccount access to the
`k8store.dominikschlosser.github.io` API group.

## Organizations

**Disabled** (`--features-disabled=organization`). With the default areas, groups are CR-backed and
the JPA organization store cannot reference them. To use Organizations you would enable the
`organization` area (`KC_SPI_DATASTORE__K8STORE__AREAS=organization`) and drop the flag. Only
[scenario 1](../01-operator-stateless) enables Organizations out of the box.

## Deploy

```bash
../../kind/kind-up.sh            # once, shared across all scenarios

./deploy.sh                      # new instance: write mode, master realm only
./deploy.sh --preconfigured      # GitOps instance: demo realm from config/, then read-only
```

`deploy.sh` stages the provider jars (`build-providers.sh`), builds and pushes the image to the local
registry, applies the k8store CRDs (the published `keycloak-k8store-crds.yaml` bundle), PostgreSQL and
the two Keycloak replicas.

### Verify

```bash
../../test/verify.sh kc-03 master security-admin-console   # new instance
../../test/verify.sh kc-03 demo   demo-app                 # pre-configured instance
```

## The version-controlled config (`config/`)

The demo realm was bootstrapped once in write mode, then the CRs Keycloak materialized were exported
and committed (the workflow k8store recommends). `config/` holds:

- `realm.yaml`, `clients.yaml`, `client-scopes.yaml`, `roles.yaml` — the `demo` realm.
- `master-demo-realm-client.yaml`, `master-demo-realm-roles.yaml` — the `demo-realm` management
  client and admin roles that live in the **master** realm. Keycloak needs these to administer the
  demo realm, so a read-only instance that layers the demo realm onto a freshly bootstrapped master
  must carry them too.

`deploy.sh --preconfigured` applies `config/`, then flips the deployment to read-only so the CRs
become the single source of truth. Edit a CR and `kubectl apply` it (or let your GitOps controller do
it) and every replica serves the change within milliseconds, no restart.
