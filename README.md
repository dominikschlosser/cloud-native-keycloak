# cloud-native-keycloak

Six ways to run **Keycloak 26.7.0** cloud-natively, each in its own folder with its own docs, each
deployable into a **shared 2-worker [kind](https://kind.sigs.k8s.io/) cluster** in two variants:

- a **new** instance (fresh Keycloak, master realm only, configure it yourself), and
- a **pre-configured** instance (a version-controlled `demo` realm applied the GitOps way).

All six run Keycloak with the `stateless` feature (no external Infinispan). What differs is how
**configuration** (realms, clients, client scopes, roles) is version-controlled and where
**dynamic data** (users, sessions) is stored. Configuration is always version-controlled; dynamic
data always lives in a database.

A distinction that runs through everything below: in **scenarios 1 and 2 the git artifact is applied
into the database** — the live configuration store is PostgreSQL, and the CR/HCL is desired state
that a controller reconciles. In **scenarios 3-6 the git artifact is the store itself** — the CRs or
YAML files Keycloak reads are the committed files.

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
[k8store](https://github.com/dominikschlosser/keycloak-k8store) `0.1.5`,
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

Factual characteristics per scenario, along the dimensions that distinguish them.

### 1 · operator-stateless
- **Config lives in:** PostgreSQL. The `KeycloakRealmImport` CR is applied into the database; the
  running store is the database, not the CR. Edits made through the console or API after import are
  not written back to the CR, so the CR and the live config can diverge.
- **Applying changes:** edit the CR and re-apply; the operator re-runs the import.
- **Backup/restore:** back up the PostgreSQL database (`pg_dump`, `kc.sh export`). The CR reproduces
  the imported subset, not later runtime edits.
- **Config surface:** the realm import is Keycloak's full realm representation. The `Keycloak` CR
  exposes a subset of server options as fields; other options go through `additionalOptions`, which
  takes server config keys only. Custom provider jars, themes, and arbitrary pod/container fields are
  not expressible through the CR and require a custom image or `spec.unsupported.podTemplate`.
- **Zero-downtime upgrades:** the operator rolls the StatefulSet; database schema migrations run on
  the new version.
- **Requires:** the Keycloak Operator and a relational database. Supports Organizations.

### 2 · terraform
- **Config lives in:** PostgreSQL. `terraform apply` writes config into the database through the admin
  API; the running store is the database. The HCL plus Terraform state is desired state, and
  out-of-band edits show up as drift on the next `plan`.
- **Applying changes:** edit the HCL and re-run `terraform apply`; the provider reconciles the server.
  `terraform plan` shows the diff.
- **Backup/restore:** back up the database. The HCL plus a persisted state backend reproduces the
  config.
- **Config surface:** the provider exposes a defined set of resources (realms, clients, scopes, roles,
  flows, and more) with HCL interpolation and modules, and can manage systems beyond Keycloak. It does
  not cover every Keycloak feature; support for a new feature lands after a provider release.
- **Zero-downtime upgrades:** rolling update of the Deployment; database schema migrations run.
  Tracking config across upgrades needs a persisted state backend.
- **Requires:** Terraform (or OpenTofu), the provider, a state backend, and a relational database.
  Supports Organizations.

### 3 · k8store-postgres
- **Config lives in:** Kubernetes CRs (etcd); the committed manifests are the source and read-only
  mode makes them authoritative. Users and sessions live in PostgreSQL.
- **Applying changes:** `kubectl apply` a CR; every replica serves it within milliseconds, no restart.
  Read-only mode rejects config writes through Keycloak.
- **Backup/restore:** the CR manifests in git are the config backup (also recoverable from etcd). Back
  up PostgreSQL for users and sessions.
- **Config surface:** CRs hold Keycloak's own representation JSON verbatim, so any field an export
  produces is expressible.
- **Zero-downtime upgrades:** rolling update; each replica keeps an in-memory CR mirror. CRD schemas
  regenerate on a Keycloak version bump and apply without downtime; database migrations run.
- **Requires:** the k8store CRDs, RBAC on the `k8store.dominikschlosser.github.io` API group, and a
  relational database. No Organizations with the default areas.

### 4 · k8store-cassandra
- **Config lives in:** Kubernetes CRs (as scenario 3). Users and sessions live in Cassandra.
- **Applying changes:** as scenario 3.
- **Backup/restore:** CR manifests in git / etcd for config; Cassandra (`nodetool snapshot`) for
  dynamic data.
- **Config surface:** as scenario 3.
- **Multi-datacenter:** Cassandra replicates across datacenters with per-DC `LOCAL_QUORUM`, which a
  single relational primary does not provide. With `stateless` (sessions in the datastore, not
  Infinispan), this supports active-active across sites without cross-site Infinispan session
  replication.
- **Zero-downtime upgrades:** rolling update; Cassandra schema migrations run on startup
  (`cassandra-migration`). No relational database.
- **Requires:** the k8store CRDs and RBAC, Cassandra, and the driver `application.conf` (see the
  scenario README). No Organizations.

### 5 · filestore-postgres
- **Config lives in:** YAML files — baked into the image (read-only variant) or on a per-pod volume
  (writable variant). Users and sessions live in PostgreSQL.
- **Applying changes:** rebuild the image (or write the file) and roll out. A running instance loads
  the files once and does not observe later edits.
- **Backup/restore:** the YAML files in git / the image are the config backup. Back up PostgreSQL for
  users and sessions.
- **Config surface:** files hold Keycloak's representation, identity providers included.
- **Zero-downtime upgrades:** rolling update replaces pods with the new image; database migrations
  run. Config is per-pod, so during the rollout window each pod serves its own image's config.
- **Requires:** a relational database; no custom API group. No Organizations. The writable variant
  runs one replica (per-pod files are not shared).

### 6 · filestore-cassandra
- **Config lives in:** YAML files in the image (as scenario 5). Users and sessions live in Cassandra.
- **Applying changes:** as scenario 5.
- **Backup/restore:** YAML files in git / image for config; Cassandra for dynamic data.
- **Config surface:** as scenario 5.
- **Multi-datacenter:** as scenario 4 (Cassandra multi-DC `LOCAL_QUORUM`, active-active with
  `stateless`).
- **Zero-downtime upgrades:** rolling update; Cassandra schema migrations on startup. No relational
  database.
- **Requires:** Cassandra and the driver `application.conf`. No Organizations. Writable variant is
  single-replica.

### Zero-downtime upgrades — what makes them work

All six run with `stateless`, so user sessions live in the datastore (database, CRs, or Cassandra),
not in an embedded Infinispan cache. Pod replacement during a rolling update therefore does not drop
sessions, which is the precondition for a zero-downtime version upgrade. The two-replica scenarios
keep at least one Ready replica serving through the Service during the roll (`maxUnavailable: 1`,
`maxSurge: 0`); the single-replica writable filestore variant is the exception. Verified here by
sending continuous requests through the Service during a `rollout restart` (`test/rollout-availability.sh`)
and observing no failed requests. Cross-version compatibility (schema/CR/file migrations between two
Keycloak versions) is per-store as noted above and is not exercised by this repo, which pins 26.7.0.

## How config is version-controlled per scenario

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
