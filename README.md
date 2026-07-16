# cloud-native-keycloak

> 📝 This repository accompanies the blog post
> [Cloud-Native Keycloak: Zero-Downtime Deployments in Practice](https://dominikschlosser.github.io/blog/2026/07/15/cloud-native-keycloak-zero-downtime.html).

Seven ways to run **Keycloak 26.7.0** cloud-natively, each in its own folder with its own docs, each
deployable into a **shared 2-worker [kind](https://kind.sigs.k8s.io/) cluster** in two variants:

- a **new** instance (fresh Keycloak, master realm only, configure it yourself)
- a **pre-configured** instance (a version-controlled `demo` realm applied the GitOps way)

All seven run Keycloak with the `stateless` feature (no external Infinispan). What differs is how
**configuration** (realms, clients, client scopes, roles) is version-controlled and where
**dynamic data** (users, sessions) is stored. Configuration is always version-controlled. Dynamic
data always lives in a database.

One distinction is where the config data lives: In **scenarios 1-3 the git artifact is applied
into the database**. The live configuration store is PostgreSQL. The CR, HCL, or realm file is desired
state that a controller reconciles into it. In **scenarios 4-7 the git artifact is the store**. The
CRs or YAML files Keycloak reads are the committed files themselves.

## The seven scenarios

| # | Scenario | Config store | Dynamic store | Relational DB | Organizations | Config as |
|---|---|---|---|:-------------:|:---:|---|
| 1 | [operator-stateless](scenarios/01-operator-stateless) | PostgreSQL | PostgreSQL |      yes      | yes | `KeycloakRealmImport` + `KeycloakOIDCClient` CRs |
| 2 | [terraform](scenarios/02-terraform) | PostgreSQL | PostgreSQL |      yes      | yes | Terraform HCL |
| 3 | [keycloak-config-cli](scenarios/03-keycloak-config-cli) | PostgreSQL | PostgreSQL |      yes      | yes | realm config YAML |
| 4 | [k8store-postgres](scenarios/04-k8store-postgres) | Kubernetes CRs | PostgreSQL |      yes      | no | k8store CR manifests |
| 5 | [k8store-cassandra](scenarios/05-k8store-cassandra) | Kubernetes CRs | Cassandra |      no       | no | k8store CR manifests |
| 6 | [filestore-postgres](scenarios/06-filestore-postgres) | YAML files | PostgreSQL |      yes      | no | filestore YAML files |
| 7 | [filestore-cassandra](scenarios/07-filestore-cassandra) | YAML files | Cassandra |      no       | no | filestore YAML files |

Scenarios 4-7 use community datastore extensions:
[k8store](https://github.com/dominikschlosser/keycloak-k8store),
[keycloak-cassandra-extension](https://github.com/opdt/keycloak-cassandra-extension), and
[keycloak-extension-filestore](https://github.com/dominikschlosser/keycloak-extension-filestore). 
Each selects a datastore (`--spi-datastore--provider=...`) and self-configures the rest.
Scenarios 1-3 use unmodified upstream Keycloak (config applied through the admin API).

## Organizations

**Only scenarios 1, 2, and 3 support Keycloak Organizations** (they use standard Keycloak storage).
The extension-based scenarios disable the feature:

- **k8store** (scenarios 4, 5): the default areas keep groups in CRs, and the JPA organization store
  cannot reference CR-backed groups. Organizations would need the opt-in `organization` area.
- **filestore** and **cassandra** (scenarios 5, 6, 7): the extensions do not implement Organizations.

The pre-configured demo realm in scenario 1 includes an Organization to show it working.

## Quickstart

```bash
kind/kind-up.sh                              # 1 control-plane + 2 workers + local registry (once)

scenarios/04-k8store-postgres/deploy.sh                  # a new instance, or
scenarios/04-k8store-postgres/deploy.sh --preconfigured  # the version-controlled demo realm

test/verify.sh kc-04 master security-admin-console       # new: REST + browser login + clients page
test/verify.sh kc-04 demo   demo-app                     # pre-configured

kind/kind-down.sh                            # tear it all down
```

Every scenario follows the same shape (`deploy.sh [--preconfigured]`, then `test/verify.sh`). Each
deploys into its own namespace (`kc-01` … `kc-07`). They do not collide and can run one after another
on the one cluster.

The kind cluster publishes the Keycloak Service NodePorts on the host. A deployed scenario is
reachable directly at **http://localhost:8080** (admin console, admin/admin) and
**http://localhost:9000** (health/metrics) with no port-forward. One scenario is deployed at a time,
so they share the fixed NodePorts.

## Comparison across dimensions

Factual characteristics per scenario, along the dimensions that distinguish them.

### 1 · operator-stateless
- **Config lives in:** PostgreSQL. The `KeycloakRealmImport` CR is applied into the database at
  import. The database is the running store. Edits made through the console or API after import stay
  in the database (they are not exported back to the CR), so the CR and the live config can diverge.
- **Applying changes:** edit the CR and re-apply. The operator re-runs the import.
- **Backup/restore:** back up the PostgreSQL database (`pg_dump`, `kc.sh export`). The CR reproduces
  the imported subset (not later runtime edits).
- **Config surface:** the realm import is Keycloak's full realm representation. The `Keycloak` CR
  exposes a subset of server options as fields. Other options go through `additionalOptions` (server
  config keys only). Custom provider jars, themes, and arbitrary pod/container fields are not
  expressible through the CR (they need a custom image or `spec.unsupported.podTemplate`).
- **Re-sync reliability:** `KeycloakRealmImport` uses the Admin REST API v1, which does not diff
  cleanly, so re-importing can recreate sub-resources it should leave alone (notably authentication
  flows) and break in-flight logins, sometimes needing a manual DB fix or a full reset and re-import.
  26.7.0 adds a validated, declarative path on the new **Admin API v2** through the operator's
  `KeycloakOIDCClient` and `KeycloakSAMLClient` CRs, but it covers clients only so far.
- **Config drift:** the database is always writable through the console and admin API. There is no
  store-level read-only. Preventing unintended config changes has to be done inside Keycloak with
  fine-grained admin permissions (role configuration). Scenarios 4-7 can instead reject all config
  writes at the store (read-only mode, or read-only files).
- **Zero-downtime upgrades:** the operator rolls the StatefulSet. Database schema migrations run on
  the new version.
- **Requires:** the Keycloak Operator and a relational database. Supports Organizations.
- **When to use:** you want stock, fully supported Keycloak (Organizations and every feature) and accept a relational database and config that lives in the database.

### 2 · terraform
- **Config lives in:** PostgreSQL. `terraform apply` writes config into the database through the admin
  API. The database is the running store. The HCL plus Terraform state is desired state, and
  out-of-band edits show up as drift on the next `plan`.
- **Applying changes:** edit the HCL and re-run `terraform apply`. The provider reconciles the server.
  `terraform plan` shows the diff.
- **Backup/restore:** back up the database. The HCL plus a persisted state backend reproduces the
  config.
- **Config surface:** the provider exposes a defined set of resources (realms, clients, scopes, roles,
  flows, and more) with HCL interpolation and modules, and can manage systems beyond Keycloak. It does
  not cover every Keycloak feature (support for a new feature lands after a provider release).
- **Re-sync reliability:** the provider applies through the Admin REST API v1. Re-applying can
  recreate resources it does not diff cleanly (for example authentication flows) and break logins,
  sometimes needing a DB fix or a reset and re-import. Only clients have a validated declarative path
  today (Admin API v2).
- **Config drift:** the database is always writable. `terraform plan` surfaces drift, and reconciling
  means re-running apply. As with the operator, blocking config changes at the source needs Keycloak
  admin RBAC (there is no store-level read-only).
- **Zero-downtime upgrades:** rolling update of the Deployment. Database schema migrations run.
  Tracking config across upgrades needs a persisted state backend.
- **Requires:** Terraform (or OpenTofu), the provider, a state backend, and a relational database.
  Supports Organizations.
- **When to use:** your platform already runs Terraform and you want config as reviewable HCL with plan-based drift detection, on standard storage.

### 3 · keycloak-config-cli
- **Config lives in:** PostgreSQL. keycloak-config-cli imports the realm file into the database
  through the admin API. The database is the running store. Edits made after an import can drift until
  the next run.
- **Applying changes:** edit the realm file and re-run the config-cli Job. It reconciles the realm to
  the file.
- **Backup/restore:** back up the database. The realm file reproduces the imported config.
- **Config surface:** the config is based on Keycloak's realm export format and extends it (variable
  substitution, managed and purge strategies, merge behaviors). One file manages a whole realm and
  everything in it (clients, roles, client scopes, authentication flows, identity providers, users),
  and it can manage multiple realms.
- **Re-sync reliability:** config-cli applies through the Admin REST API v1. Re-running can delete and
  recreate resources it does not diff finely (authentication flows have caused login errors during
  provisioning, adorsys/keycloak-config-cli#875), sometimes needing a DB fix or a reset and re-import.
  Only clients have a validated declarative path today (Admin API v2).
- **Config drift:** the database is always writable. Re-running config-cli reconciles the realm back
  to the file. As with the operator and terraform, there is no store-level read-only.
- **Zero-downtime upgrades:** rolling update of the Deployment. Database schema migrations run.
- **Requires:** a relational database and the `adorsys/keycloak-config-cli` image. Supports
  Organizations.
- **When to use:** you want declarative realm config as Keycloak's own realm representation, applied
  and reconciled by a simple Job, on standard storage.

### 4 · k8store-postgres
- **Config lives in:** Kubernetes CRs (etcd). The committed manifests are the source, and read-only
  mode makes them authoritative. Users and sessions live in PostgreSQL.
- **Applying changes:** `kubectl apply` a CR. Every replica serves it within milliseconds, no restart.
  Read-only mode rejects config writes through Keycloak.
- **Backup/restore:** the CR manifests in git are the config backup (also recoverable from etcd). Back
  up PostgreSQL for users and sessions.
- **Config surface:** CRs hold Keycloak's own representation JSON verbatim, so any field an export
  produces is expressible.
- **Re-sync reliability:** config is served from the CRs directly, not imported through the Admin REST
  API, so it avoids the Admin API v1 re-sync problems (recreated authentication flows, and similar)
  that affect scenarios 1-3.
- **Config drift:** the pre-configured instance runs read-only, so Keycloak rejects all config writes
  and the committed CRs stay authoritative (no in-Keycloak RBAC needed to keep git the source of
  truth). The empty instance runs writable for click-config.
- **Zero-downtime upgrades:** rolling update. Each replica keeps an in-memory CR mirror. CRD schemas
  regenerate on a Keycloak version bump and apply without downtime. Database migrations run.
- **Requires:** the k8store CRDs, RBAC on the `k8store.dominikschlosser.github.io` API group, and a
  relational database. No Organizations with the default areas.
- **When to use:** you want GitOps-native config as Kubernetes CRs (applied by kubectl or ArgoCD, served read-only) with a relational database for users and sessions.

### 5 · k8store-cassandra
- **Config lives in:** Kubernetes CRs (as scenario 4). Users and sessions live in Cassandra.
- **Applying changes:** as scenario 4.
- **Backup/restore:** CR manifests in git (or etcd) for config. Cassandra (`nodetool snapshot`) for
  dynamic data.
- **Config surface:** as scenario 4.
- **Multi-datacenter:** Cassandra replicates across datacenters with per-DC `LOCAL_QUORUM`, which a
  single relational primary does not provide. With `stateless` (sessions in the datastore, not an
  Infinispan cache), this supports active-active across sites without cross-site Infinispan session
  replication.
- **Zero-downtime upgrades:** rolling update. Cassandra schema migrations run on startup
  (`cassandra-migration`). No relational database.
- **Requires:** the k8store CRDs and RBAC, Cassandra, and the driver `application.conf` (see the
  scenario README). No Organizations.
- **When to use:** you want CR-based GitOps config and a dynamic store that spans datacenters (active-active)... or already use Cassandra, for example in a 2 datacenter setup.

### 6 · filestore-postgres
- **Config lives in:** YAML files, baked into the image (read-only variant) or on a per-pod volume
  (writable variant). Users and sessions live in PostgreSQL.
- **Applying changes:** rebuild the image (or write the file) and roll out. A running instance loads
  the files once and does not observe later edits.
- **Backup/restore:** the YAML files in git (and the image) are the config backup. Back up PostgreSQL
  for users and sessions.
- **Config surface:** files hold Keycloak's representation, identity providers included.
- **Re-sync reliability:** config is served from the files directly, not imported through the Admin
  REST API, so it avoids the Admin API v1 re-sync problems that affect scenarios 1-3.
- **Config drift:** the pre-configured instance mounts the files read-only (baked into the image), so
  the committed files stay authoritative. The empty instance runs writable on a per-pod volume.
- **Zero-downtime upgrades:** rolling update replaces pods with the new image. Database migrations
  run. Config is per-pod, so during the rollout window each pod serves its own image's config.
- **Requires:** a relational database. No custom API group. No Organizations. The writable variant
  runs one replica (per-pod files are not shared).
- **When to use:** you want file-based config mounted read-only, with a relational database, and can accept per-pod config (a single writable replica).

### 7 · filestore-cassandra
- **Config lives in:** YAML files in the image (as scenario 6). Users and sessions live in Cassandra.
- **Applying changes:** as scenario 6.
- **Backup/restore:** YAML files in git (or the image) for config. Cassandra for dynamic data.
- **Config surface:** as scenario 6.
- **Multi-datacenter:** as scenario 5 (Cassandra multi-DC `LOCAL_QUORUM`, active-active with
  `stateless`).
- **Zero-downtime upgrades:** rolling update. Cassandra schema migrations on startup. No relational
  database.
- **Requires:** Cassandra and the driver `application.conf`. No Organizations. Writable variant is
  single-replica.
- **When to use:** you want file-based config and a relational-database-free, multi-datacenter dynamic store (or already use Cassandra, for example in a 2 datacenter setup).

## GitOps with ArgoCD

The `--preconfigured` scenarios apply their config with a script. [`scenarios/08-argocd/`](scenarios/08-argocd) runs the same
k8store + PostgreSQL setup through **ArgoCD** instead. ArgoCD syncs Keycloak and the CRs from an
in-cluster git server. Keycloak boots read-only, and a PostSync hook Job seeds the admin.

```bash
scenarios/08-argocd/setup.sh                              # ArgoCD + git server + the synced Application

# change config the GitOps way: clone the repo, edit a CR, push
kubectl -n argocd port-forward svc/git-server 9418:9418 &
git clone git://localhost:9418/repo /tmp/keycloak-gitops
# edit /tmp/keycloak-gitops/config/realms.yaml (for example the demo realm displayName), then:
cd /tmp/keycloak-gitops && git commit -am "update demo realm" && git push origin main
```

ArgoCD reconciles the commit and Keycloak serves the change with no restart (force it immediately
with `kubectl -n argocd annotate application keycloak-k8store argocd.argoproj.io/refresh=hard
--overwrite`). The ArgoCD UI is at `https://localhost:8081` (admin/admin) via
`kubectl -n argocd port-forward svc/argocd-server 8081:443`. See [scenarios/08-argocd/README.md](scenarios/08-argocd/README.md).

## Requirements

Docker, `kind`, `kubectl`, `mvn` and a JDK (to stage the provider jars from Maven Central for
scenarios 4-7), and Node.js with a local Chrome/Chromium (the browser verification uses
`puppeteer-core` against the system Chrome). Keycloak images are `quay.io/keycloak/keycloak:26.7.0`.
Scenario 2 also pulls a `hashicorp/terraform` image for the apply Job.

## Layout

```
kind/         shared cluster up/down
lib/          shared bash helpers, DB manifests, the Cassandra driver application.conf
test/         verify.sh (REST smoke + browser login + client overview) and its puppeteer script
scenarios/    one self-contained folder per scenario (README, deploy.sh, manifests, config)
```
