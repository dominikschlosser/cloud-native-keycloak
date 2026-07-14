# cloud-native-keycloak

Six ways to run **Keycloak 26.7.0** cloud-natively, each in its own folder with its own docs, each
deployable into a **shared 2-worker [kind](https://kind.sigs.k8s.io/) cluster** in two variants:

- a **new** instance (fresh Keycloak, master realm only, configure it yourself), and
- a **pre-configured** instance (a version-controlled `demo` realm applied the GitOps way).

All six run Keycloak with the `stateless` feature (no external Infinispan). What differs is how
**configuration** (realms, clients, client scopes, roles) is version-controlled and where
**dynamic data** (users, sessions) is stored. Configuration is always version-controlled; dynamic
data always lives in a database.

## The six scenarios

| # | Scenario | Config store | Dynamic store | Database-free | Organizations | Config as |
|---|---|---|---|:---:|:---:|---|
| 1 | [operator-stateless](scenarios/01-operator-stateless) | standard Keycloak | PostgreSQL | no | **yes** | `KeycloakRealmImport` CR |
| 2 | [terraform](scenarios/02-terraform) | standard Keycloak | PostgreSQL | no | **yes** | Terraform HCL |
| 3 | [k8store-postgres](scenarios/03-k8store-postgres) | Kubernetes CRs | PostgreSQL | no | no | k8store CR manifests |
| 4 | [k8store-cassandra](scenarios/04-k8store-cassandra) | Kubernetes CRs | Cassandra | yes | no | k8store CR manifests |
| 5 | [filestore-postgres](scenarios/05-filestore-postgres) | YAML files | PostgreSQL | no | no | filestore YAML files |
| 6 | [filestore-cassandra](scenarios/06-filestore-cassandra) | YAML files | Cassandra | yes | no | filestore YAML files |

Scenarios 3-6 use community datastore extensions pulled from Maven Central:
[k8store](https://github.com/dominikschlosser/keycloak-k8store) `0.1.3`,
[keycloak-cassandra-extension](https://github.com/opdt/keycloak-cassandra-extension) `6.0.0`, and
[keycloak-extension-filestore](https://github.com/dominikschlosser/keycloak-extension-filestore)
`3.0.0`. Each selects a datastore (`--spi-datastore--provider=...`) and self-configures the rest.
Scenarios 1 and 2 use unmodified upstream Keycloak.

## Organizations

**Only scenarios 1 and 2 support Keycloak Organizations**, because they use standard Keycloak storage.
The extension-based scenarios disable the feature:

- **k8store** (scenarios 3, 4): the default areas keep groups in CRs, and the JPA organization store
  cannot reference CR-backed groups. Organizations would need the opt-in `organization` area.
- **filestore** and **cassandra** (scenarios 4, 5, 6): the extensions do not implement Organizations.

The pre-configured demo realm in scenario 1 includes an Organization to show it working.

## Quickstart

```bash
kind/kind-up.sh                              # 1 control-plane + 2 workers + local registry (once)

scenarios/03-k8store-postgres/deploy.sh                  # a new instance, or
scenarios/03-k8store-postgres/deploy.sh --preconfigured  # the version-controlled demo realm

test/verify.sh kc-03 master security-admin-console       # new: REST + browser login + clients page
test/verify.sh kc-03 demo   demo-app                     # pre-configured

kind/kind-down.sh                            # tear it all down
```

Every scenario follows the same shape (`deploy.sh [--preconfigured]`, then `test/verify.sh`). Each
deploys into its own namespace (`kc-01` … `kc-06`), so they do not collide and can run one after
another on the one cluster. See each scenario's README for its exact verify command (scenario 1 sets
`CNK_KC_SVC=keycloak-service`).

## Comparison across dimensions

Each scenario's pros and cons, along the dimensions that tend to decide between them.

### 1 · operator-stateless
- **Versioning:** the realm is one `KeycloakRealmImport` CR (Keycloak's full realm representation).
  Coarse-grained (a whole realm per file), and import is one-way, so console edits after import drift
  from the committed CR.
- **Backup/restore:** standard Keycloak storage, so mature tooling applies (`pg_dump`, `kc.sh export`,
  realm import). One relational database to back up.
- **Ease of use:** highest. The official operator owns rollout, upgrades, TLS and scaling, and is
  well documented.
- **Flexibility:** the realm import covers the whole realm representation, but the `Keycloak` CR
  exposes only a subset of server options as fields; the rest go through the `additionalOptions`
  escape hatch, so server-level tuning is less direct.
- **Ops:** needs a relational database; supports Organizations and all features.

### 2 · terraform
- **Versioning:** the strongest change-management story. Fine-grained HCL resources, reviewable
  `terraform plan` diffs, and state that detects drift and reconciles the server back to the code.
- **Backup/restore:** standard storage (database backup), plus the Terraform state and code together
  reproduce the config. Production needs a real state backend (S3/GCS/database).
- **Ease of use:** familiar to platform teams, but it adds Terraform, the provider and a state
  backend to operate.
- **Flexibility:** a large curated resource set with interpolation and modules, and it can orchestrate
  systems beyond Keycloak. It does lag brand-new Keycloak features (not every field is a resource).
- **Ops:** needs a relational database; supports Organizations (standard storage).

### 3 · k8store-postgres
- **Versioning:** one CR per entity, native GitOps. `kubectl apply` is served within milliseconds with
  no restart, and read-only mode makes the CRs the single source of truth.
- **Backup/restore:** config CRs live in git (git is the backup) and in etcd; users live in
  PostgreSQL. Two systems to back up.
- **Ease of use:** kubectl-native and no rebuild to change config, but it adds custom CRDs and RBAC on
  a custom API group.
- **Flexibility:** CRs hold Keycloak's own representation JSON verbatim, so any exported field is
  expressible (high config fidelity).
- **Ops:** needs a relational database; no Organizations with the default areas.

### 4 · k8store-cassandra
- **Versioning:** same CR model as scenario 3.
- **Backup/restore:** config in git and etcd; dynamic data in Cassandra (`nodetool` snapshots), a
  different backup model than a relational database.
- **Ease of use:** the most experimental combination. Cassandra is heavier to operate, and the shaded
  driver needs a supplied `reference.conf` (handled by the image).
- **Flexibility:** high (representation CRs).
- **Ops:** fully database-free (no relational database); no Organizations.

### 5 · filestore-postgres
- **Versioning:** one YAML file per entity, very readable and easy to diff. But config is per-pod and a
  running instance does not observe file edits, so changes mean an image rebuild and rollout.
- **Backup/restore:** config is files in git, baked into the image (git is the backup); users live in
  PostgreSQL.
- **Ease of use:** the simplest format (plain files) with no custom API group, but the per-pod model
  forces a single writable replica or an image-baked read-only seed, and the seeded admin needs a
  small profile workaround.
- **Flexibility:** files hold Keycloak's representation, so high config fidelity (identity providers
  included).
- **Ops:** needs a relational database; no Organizations.

### 6 · filestore-cassandra
- **Versioning:** same file model as scenario 5.
- **Backup/restore:** config in git and the image; dynamic data in Cassandra.
- **Ease of use:** files are simple, but this combines filestore's per-pod caveats with Cassandra's
  operational weight and the driver `reference.conf` workaround.
- **Flexibility:** high (representation files).
- **Ops:** fully database-free; no Organizations.

## How config is version-controlled per scenario

Config areas (realms, clients, client scopes, roles) are always in git; dynamic areas (users,
sessions) always in the database. The mechanism differs:

- **Scenario 1** — a `KeycloakRealmImport` CR carrying the realm JSON, imported by the operator.
- **Scenario 2** — Terraform HCL applied against the admin API by a one-shot Job.
- **Scenarios 3-4** — one CR manifest per entity (`KeycloakRealm`, `KeycloakClient`, …), applied with
  `kubectl`. Read-only mode makes them authoritative.
- **Scenarios 5-6** — one YAML file per entity, baked into the image as a read-only seed.

For scenarios 3-6 the demo realm was bootstrapped once in write mode and its materialized config
exported and committed, which is the workflow those stores recommend.

## Requirements

Docker, `kind`, `kubectl`, `mvn` and a JDK (to stage the provider jars from Maven Central for
scenarios 3-6), and Node.js with a local Chrome/Chromium (the browser verification uses
`puppeteer-core` against the system Chrome). Keycloak images are `quay.io/keycloak/keycloak:26.7.0`;
scenario 2 also pulls a `hashicorp/terraform` image for the apply Job.

## Layout

```
kind/         shared cluster up/down
lib/          shared bash helpers, DB manifests, the Cassandra driver reference.conf
test/         verify.sh (REST smoke + browser login + client overview) and its puppeteer script
scenarios/    one self-contained folder per scenario (README, deploy.sh, manifests, config)
```
