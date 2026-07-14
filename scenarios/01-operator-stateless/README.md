# Scenario 1 — standard Keycloak, Operator + stateless feature + PostgreSQL

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
    enabled: [stateless]
  http: { httpEnabled: true }
  hostname: { strict: false }
  ingress: { enabled: false }
  bootstrapAdmin: { user: { secret: keycloak-admin } }
```

`stateless` keeps only an embedded local cache and moves session and auth state into the database,
so there is no external Infinispan to operate. `ingress.enabled: false` and `http.httpEnabled: true`
keep it reachable through the operator's Service in kind (no ingress controller). The bootstrap admin
(admin/admin) comes from the `keycloak-admin` Secret.

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

The operator creates a ClusterIP Service (`keycloak-service`); `manifests/20-keycloak-nodeport.yaml`
adds a NodePort Service named `keycloak` selecting the same pods, so `http://localhost:8080` works and
`test/verify.sh` finds the Service under its default name.

## The version-controlled config (`config/realm-demo.yaml`)

A `KeycloakRealmImport` CR carries the `demo` realm (client `demo-app`, client scope `demo-scope`,
role `demo-role`, and an Organization `demo-org`). Applying it makes the operator run an import Job
that materializes the realm. This is the GitOps mechanism for the standard setup: the realm lives in
git, the operator applies it, and dynamic data (users, sessions) stays in the database.
