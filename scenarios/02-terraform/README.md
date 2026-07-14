# Scenario 2: Terraform provider + PostgreSQL

Stock Keycloak 26.7.0 (no datastore extension) with PostgreSQL and the `stateless` feature, where the
configuration is managed by the
[keycloak/keycloak](https://registry.terraform.io/providers/keycloak/keycloak/latest) **Terraform
provider**. Realms, clients, client scopes and roles are declared as Terraform resources in
`config/main.tf`. The provider applies them through the Keycloak admin API. Dynamic data (users,
sessions) lives in the database.

## How it works

Keycloak is a plain Deployment of the unmodified upstream image (`manifests/10-keycloak.yaml`), two
replicas against PostgreSQL. No custom image and no build.

The pre-configured variant runs a one-shot Kubernetes Job (`manifests/terraform-job.yaml`, the
`hashicorp/terraform` image) that mounts `config/main.tf` from a ConfigMap and runs
`terraform init && terraform apply`. The provider block points at the in-cluster Service:

```hcl
provider "keycloak" {
  client_id = "admin-cli"
  username  = "admin"
  password  = "admin"
  url       = "http://keycloak:8080"
}
```

Terraform state is kept in the Job pod, so this is a one-shot apply (create the demo realm). A real
setup would use a remote backend (S3, GCS, a database) so state persists and `plan` shows drift.

## Organizations

**Supported** (standard Keycloak storage), the same as [scenario 1](../01-operator-stateless). The
demo config here manages realm, client, scope and role for parity with the other scenarios;
Organizations would be an additional resource. The extension-based scenarios (3-6) cannot enable the
feature.

## Deploy

```bash
../../kind/kind-up.sh            # once, shared across all scenarios

./deploy.sh                      # new instance: stock Keycloak, master realm only
./deploy.sh --preconfigured      # runs `terraform apply` to create the demo realm
```

### Verify

```bash
../../test/verify.sh kc-02 master security-admin-console   # new instance
../../test/verify.sh kc-02 demo   demo-app                 # pre-configured instance
```

## The version-controlled config (`config/main.tf`)

One HCL file declaring the `demo` realm, the `demo-app` client, the `demo-scope` client scope and the
`demo-role` role. Terraform's plan/apply model means changes are reviewable diffs and the provider
reconciles the live server to match the code. The trade-off is that the provider exposes a curated
set of resources (it can lag new Keycloak features), and you own the state backend.
