# Scenario 3: keycloak-config-cli + PostgreSQL

Stock Keycloak 26.7.0 (no datastore extension) with PostgreSQL and the `stateless` feature, where the
configuration is managed by [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli).
The config in `config/demo-realm.yaml` is based on Keycloak's realm export format and extends it
(variable substitution, managed and purge strategies). It manages the whole realm and everything in it
(clients, roles, client scopes, authentication flows, identity providers, users), and it can manage
multiple realms. A one-shot Job imports it through the admin API and keeps Keycloak reconciled to the
files. Dynamic data (users, sessions) lives in the database.

## How it works

Keycloak is a plain Deployment of the unmodified upstream image (`manifests/10-keycloak.yaml`), two
replicas against PostgreSQL. No custom image and no build.

The pre-configured variant runs the `adorsys/keycloak-config-cli` Job (`manifests/config-cli-job.yaml`).
It mounts `config/demo-realm.yaml` from a ConfigMap, waits for Keycloak, then imports and reconciles
the realm:

```
KEYCLOAK_URL=http://keycloak:8080
KEYCLOAK_USER=admin / KEYCLOAK_PASSWORD=admin
IMPORT_FILES_LOCATIONS=/config/*.yaml
```

Re-running the Job reconciles the live config back to the committed files, so this is declarative
config management like [scenario 2](../02-terraform), using Keycloak's realm config format instead of
a provider's resource model.

## Organizations

**Supported** (standard Keycloak storage), the same as scenarios 1 and 2. The demo config manages
realm, client, scope and role for parity with the other scenarios. Organizations can be added to the
realm file. The extension-based scenarios (4-7) cannot enable the feature.

## Deploy

```bash
../../kind/kind-up.sh            # once, shared across all scenarios

./deploy.sh                      # new instance: stock Keycloak, master realm only
./deploy.sh --preconfigured      # imports the demo realm with keycloak-config-cli
```

### Verify

```bash
../../test/verify.sh kc-03 master security-admin-console   # new instance
../../test/verify.sh kc-03 demo   demo-app                 # pre-configured instance
```

## Config in the database

The realm file is desired state that config-cli applies into Keycloak. The live store is PostgreSQL,
so console or API edits made after an import can drift until the next run. Like scenarios 1 and 2,
there is no store-level read-only. Restricting config changes needs Keycloak admin RBAC.
