# Scenario 1: standard Keycloak, Operator + stateless feature + PostgreSQL

Stock Keycloak 26.7.0 managed by the official **Keycloak Operator**, running with the `stateless`
feature and a PostgreSQL database. No datastore extension and no custom image. This is the reference
cloud-native setup and the **only scenario that supports Organizations**.

## How it works

The operator (installed from `keycloak/keycloak-k8s-resources` at tag `26.7.0`) reconciles a
`Keycloak` custom resource into a StatefulSet, a Service and the rest. The CR (`manifests/10-keycloak.yaml`)
requests two instances, a Postgres database, and enables the `stateless` feature:

```yaml
spec:
  instances: 2
  db: { vendor: postgres, host: postgres, ... }
  features:
    enabled: [stateless, client-admin-api:v2]
  http: { httpEnabled: true }
  hostname: { strict: false }
  ingress: { enabled: false }
  bootstrapAdmin:
    user: { secret: keycloak-admin }       # console login (username/password)
    service: { secret: keycloak-admin }     # operator's Admin API v2 client (client-id/client-secret)
```

`stateless` keeps only an embedded local cache and moves session and auth state into the database,
so there is no external Infinispan to operate. `ingress.enabled: false` and `http.httpEnabled: true`
keep it reachable through the operator's Service in kind (no ingress controller). The bootstrap admin
(admin/admin) comes from the `keycloak-admin` Secret.

`client-admin-api:v2` turns on the Admin API v2 so the operator can manage clients declaratively (see
below). For that the operator authenticates as a service account, so the `keycloak-admin` Secret also
carries `client-id` and `client-secret` keys, referenced by `bootstrapAdmin.service`.

## Organizations

**Supported and enabled here.** Standard Keycloak storage backs Organizations, so the pre-configured
demo realm defines one (`demo-org`). The other scenarios use datastore extensions
(k8store default areas, filestore, cassandra) that do not support Organizations, so they disable the
feature.

## Deploy

```bash
../../kind/kind-up.sh            # once, shared across all scenarios

./deploy.sh                      # new instance: operator-managed Keycloak, master realm only
./deploy.sh --preconfigured      # additionally imports the version-controlled demo realm
```

### Verify

```bash
../../test/verify.sh kc-01 master security-admin-console   # new instance
../../test/verify.sh kc-01 demo   demo-app                 # pre-configured
```

The operator creates a ClusterIP Service (`keycloak-service`). `manifests/20-keycloak-nodeport.yaml`
adds a NodePort Service named `keycloak` selecting the same pods (so `http://localhost:8080` works and
`test/verify.sh` finds it under the default Service name).

## Version-controlled config (realm and client CRs)

The operator reconciles two kinds of config CR, each through a different admin API:

- `config/realm-demo.yaml` is a `KeycloakRealmImport` CR carrying the whole `demo` realm (client
  `demo-app`, client scope `demo-scope`, role `demo-role`, and an Organization `demo-org`). Applying
  it makes the operator run an import Job (Admin API v1) that materializes the realm.
- `config/client-demo-oidc.yaml` is a `KeycloakOIDCClient` CR managing a single client
  (`demo-oidc-app`) declaratively through Admin API v2 (new in 26.7.0). The client id is the CR
  `metadata.name`, and the operator reconciles just that one client rather than a whole realm.
  `KeycloakSAMLClient` does the same for SAML clients.

This is the GitOps mechanism for the standard setup: config lives in git, the operator applies it, and
dynamic data (users, sessions) stays in the database. Realm-level config still goes through the v1
import (the operator does not yet expose realms, roles or flows as CRs), while clients can now be
managed one resource at a time through v2.
