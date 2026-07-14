# Scenario 5: filestore (config in YAML files) + PostgreSQL (dynamic)

Keycloak 26.7.0 with the
[filestore](https://github.com/dominikschlosser/keycloak-extension-filestore) datastore extension.
Configuration entities (realms, clients, client scopes, roles, groups, identity providers) are read
from **YAML files on disk**. Users and sessions live in **PostgreSQL**. The files are your
version-controlled source of truth, typically mounted read-only (a ConfigMap, or here baked into the
image).

## How it works

The image (`Dockerfile`) bakes the filestore provider jars into Keycloak and runs `kc.sh build`:

```
--features=stateless --db=postgres --spi-datastore--provider=file \
--features-disabled=authorization,admin-fine-grained-authz,organization
```

Selecting `file` as the datastore is the opt-in. It self-configures from there (disables the JPA
realm provider and the realm/authz/organization caches). One YAML file per entity, laid out as
`<dir>/<realm>.yaml`, `<dir>/<realm>/clients/*.yaml`, `.../roles/*.yaml`, etc. The directory is set
by `KC_SPI_MAP_STORAGE__FILE__DIR`.

`KC_SPI_DATASTORE__FILE__RESOURCES_VERSION_SEED` pins the theme `/resources/{tag}/` cache-buster.
filestore owns the deployment state provider even with a database, and without a stable seed the tag
it writes into the admin console HTML does not match what it serves, so the console assets 404 and
never load.

## Two variants, two topologies

filestore config is **per-pod** (there is no shared API like k8store's CRs), so the topology differs:

- **new**: one replica, writable filestore on a `PersistentVolumeClaim`. A single replica avoids a
  split brain across pods, and the volume keeps the master realm (and its role ids) consistent with
  the admin user and role mappings that live in PostgreSQL across restarts.
- **--preconfigured**: the committed `config/filestore/` is baked into the image as a read-only
  seed, identical on every pod, so it runs two replicas pinned to separate workers.

## Organizations

**Disabled** (`--features-disabled=...,organization`). filestore does not support Organizations. Only
[scenario 1](../01-operator-stateless) enables them.

## Deploy

```bash
../../kind/kind-up.sh            # once, shared across all scenarios

./deploy.sh                      # new instance: 1 replica, writable PVC, master realm only
./deploy.sh --preconfigured      # GitOps instance: demo realm from the baked seed, 2 replicas
```

### Verify

```bash
../../test/verify.sh kc-05 master security-admin-console   # new instance
../../test/verify.sh kc-05 demo   demo-app                 # pre-configured instance
```

## The version-controlled config (`config/filestore/`)

Bootstrapped once in write mode, then the whole filestore directory was copied out and committed. It
holds the `master` and `demo` realms (`master.yaml`, `demo.yaml`, and their `clients/`,
`client-scopes/`, `roles/` subtrees). Because the export carries the full master realm, it includes
the `demo-realm` management client the master admin needs to administer the demo realm.

Two details the deploy handles for the pre-configured instance, both because the seed already contains
the master realm (so the usual `KC_BOOTSTRAP_ADMIN` never fires):

- a one-shot **Job** runs `kc.sh bootstrap-admin` to seed an admin user into the database, and
- the deploy then completes that admin's profile (email and name), which `bootstrap-admin` does not
  set but the realm's default user profile requires.

Editing a file under `config/filestore/` and rebuilding the image republishes the config. filestore
never observes out-of-band edits to a running instance (the store is loaded once), so config changes
mean a rollout.
