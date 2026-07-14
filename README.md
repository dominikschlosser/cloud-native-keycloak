# cloud-native-keycloak

Five ways to run **Keycloak 26.7.0** cloud-natively, each in its own folder with its own docs, each
deployable into a **shared 2-worker [kind](https://kind.sigs.k8s.io/) cluster** in two variants:

- a **new** instance (fresh Keycloak, master realm only, configure it yourself), and
- a **pre-configured** instance (a version-controlled `demo` realm applied the GitOps way).

All five run Keycloak with the `stateless` feature (no external Infinispan). What differs is where
**configuration** (realms, clients, client scopes, roles) and **dynamic data** (users, sessions)
are stored. Configuration is always version-controlled; dynamic data always lives in a database.

## The five scenarios

| # | Scenario | Config store | Dynamic store | Database-free | Organizations | Config as |
|---|---|---|---|:---:|:---:|---|
| 1 | [operator-stateless](scenarios/01-operator-stateless) | standard Keycloak | PostgreSQL | no | **yes** | `KeycloakRealmImport` CR |
| 2 | [k8store-postgres](scenarios/02-k8store-postgres) | Kubernetes CRs | PostgreSQL | no | no | k8store CR manifests |
| 3 | [k8store-cassandra](scenarios/03-k8store-cassandra) | Kubernetes CRs | Cassandra | yes | no | k8store CR manifests |
| 4 | [filestore-postgres](scenarios/04-filestore-postgres) | YAML files | PostgreSQL | no | no | filestore YAML files |
| 5 | [filestore-cassandra](scenarios/05-filestore-cassandra) | YAML files | Cassandra | yes | no | filestore YAML files |

Scenarios 2-5 use community datastore extensions pulled from Maven Central:
[k8store](https://github.com/dominikschlosser/keycloak-k8store) `0.1.3`,
[keycloak-cassandra-extension](https://github.com/opdt/keycloak-cassandra-extension) `6.0.0`, and
[keycloak-extension-filestore](https://github.com/dominikschlosser/keycloak-extension-filestore)
`3.0.0`. Each selects a datastore (`--spi-datastore--provider=...`) and self-configures the rest.

## Organizations

**Only scenario 1 supports Keycloak Organizations**, because it uses standard Keycloak storage. The
extension-based scenarios disable the feature:

- **k8store** (scenarios 2, 3): the default areas keep groups in CRs, and the JPA organization store
  cannot reference CR-backed groups. Organizations would need the opt-in `organization` area.
- **filestore** and **cassandra** (scenarios 3, 4, 5): the extensions do not implement Organizations.

The pre-configured demo realm in scenario 1 includes an Organization to show it working.

## Quickstart

```bash
kind/kind-up.sh                              # 1 control-plane + 2 workers + local registry (once)

scenarios/02-k8store-postgres/deploy.sh                  # a new instance, or
scenarios/02-k8store-postgres/deploy.sh --preconfigured  # the version-controlled demo realm

test/verify.sh kc-02 master security-admin-console       # new: REST + browser login + clients page
test/verify.sh kc-02 demo   demo-app                     # pre-configured

kind/kind-down.sh                            # tear it all down
```

Every scenario follows the same shape (`deploy.sh [--preconfigured]`, then `test/verify.sh`). Each
deploys into its own namespace (`kc-01` … `kc-05`), so they do not collide and can run one after
another on the one cluster. See each scenario's README for its exact verify command (scenario 1 sets
`CNK_KC_SVC=keycloak-service`).

## Pros and cons

### 1 · operator-stateless
- **Pros:** stock Keycloak, nothing experimental; the official Operator handles rollout and upgrades;
  the only scenario with Organizations and full feature support; realm import is well documented.
- **Cons:** config lives in the database after import (the CR is the source, but drift is possible);
  needs a relational database; heavier than a plain Deployment.

### 2 · k8store-postgres
- **Pros:** config is Kubernetes CRs, so GitOps is native (`kubectl apply`, no restart, changes served
  in milliseconds); every replica mirrors the CRs in memory; read-only mode makes the CRs the single
  source of truth.
- **Cons:** needs a relational database for users and sessions; requires RBAC on a custom API group;
  no Organizations with the default areas.

### 3 · k8store-cassandra
- **Pros:** fully database-free (config in CRs, dynamic data in Cassandra); Cassandra scales
  horizontally with no primary; keeps k8store's GitOps model for config.
- **Cons:** the most experimental combination; Cassandra is heavier to operate; no Organizations; the
  shaded driver needs a supplied `reference.conf` (handled by the image).

### 4 · filestore-postgres
- **Pros:** config is plain YAML files, easy to read and diff; simple mental model (mount files
  read-only); no custom API group or RBAC.
- **Cons:** config is per-pod, not shared, so the writable instance is single-replica and the
  read-only instance bakes the files into the image; a running instance does not observe file edits
  (config changes mean a rollout); no Organizations.

### 5 · filestore-cassandra
- **Pros:** fully database-free with the simplest possible config format (files); good for immutable,
  image-baked configuration.
- **Cons:** combines filestore's per-pod caveats with Cassandra's operational weight; no
  Organizations; the shaded driver needs a supplied `reference.conf` (handled by the image).

## How config is version-controlled per scenario

Config areas (realms, clients, client scopes, roles) are always in git; dynamic areas (users,
sessions) always in the database. The mechanism differs:

- **Scenario 1** — a `KeycloakRealmImport` CR carrying the realm JSON, imported by the operator.
- **Scenarios 2-3** — one CR manifest per entity (`KeycloakRealm`, `KeycloakClient`, …), applied with
  `kubectl`. Read-only mode makes them authoritative.
- **Scenarios 4-5** — one YAML file per entity, baked into the image as a read-only seed.

The demo realm was bootstrapped once in write mode and its materialized config exported and
committed, which is the workflow these stores recommend.

## Requirements

Docker, `kind`, `kubectl`, `mvn` and a JDK (to stage the provider jars from Maven Central), and
Node.js with a local Chrome/Chromium (the browser verification uses `puppeteer-core` against the
system Chrome). Keycloak images are `quay.io/keycloak/keycloak:26.7.0`.

## Layout

```
kind/         shared cluster up/down
lib/          shared bash helpers, DB manifests, the Cassandra driver reference.conf
test/         verify.sh (REST smoke + browser login + client overview) and its puppeteer script
scenarios/    one self-contained folder per scenario (README, deploy.sh, manifests, config)
```
