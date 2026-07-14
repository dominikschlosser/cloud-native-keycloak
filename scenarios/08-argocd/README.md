# Scenario 8: ArgoCD (real GitOps)

The other `--preconfigured` scenarios apply their config with a script. This one shows the same
k8store + PostgreSQL setup ([scenario 4](../04-k8store-postgres)) driven by **ArgoCD** instead, the
way you would run it in production. ArgoCD watches a git repo and reconciles the cluster to match it.

It is a deployment method rather than a storage option, so it reuses scenario 4's storage (k8store
CRs, where ArgoCD actually syncs the config). It has no `new`/`--preconfigured` split.

## What it sets up

- **ArgoCD** in the `argocd` namespace.
- An **in-cluster git server** (`git-server`, a small `git daemon` image seeded with `app/` at build
  time). This keeps the demo self-contained (no external repo, works offline).
- An ArgoCD **Application** (`application.yaml`) that syncs `app/` from `git://git-server:9418/repo`
  into namespace `kc-argocd`.

`app/` is a self-contained GitOps deployment:

- `10-rbac.yaml`, `20-postgres.yaml`, `30-keycloak.yaml` (Keycloak boots **read-only** from the
  start), and `config/` (the `master` and `demo` realms as k8store CRs).
- `40-bootstrap-admin-job.yaml` runs as an ArgoCD **PostSync hook**. Because master already exists as
  a CR, `KC_BOOTSTRAP_ADMIN` does not fire, so the hook seeds the admin user into the database.

## Run

```bash
../../kind/kind-up.sh          # once
./setup.sh                    # installs ArgoCD + git server, creates the Application, waits for Healthy

CNK_KC_SVC=keycloak ../../test/verify.sh kc-argocd demo demo-app   # REST + browser login + clients page
# or open http://localhost:8080 (admin/admin)

./teardown.sh       # remove the demo
```

The Keycloak image is scenario 4's (`localhost:5001/cnk-04:dev`). `setup.sh` builds it if missing.
ArgoCD only syncs manifests, so in a real setup CI builds the image and ArgoCD references it.

## ArgoCD UI

The `argocd-server` Service is ClusterIP (the kind host ports are used by Keycloak). Reach the UI
with a port-forward:

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:443
# open https://localhost:8081 (accept the self-signed cert)
# login: admin / admin
```

`setup.sh` sets the admin password to `admin` (demo only). In production leave the generated
`argocd-initial-admin-secret` password in place, or use SSO.

## Changing config the GitOps way

The git server holds a real git repo (seeded from `app/` at build time). Change config by pushing a
commit to it, the same as you would to any remote. ArgoCD reconciles the change and k8store serves it
with no restart.

```bash
kubectl -n argocd port-forward svc/git-server 9418:9418 &
git clone git://localhost:9418/repo /tmp/keycloak-gitops
cd /tmp/keycloak-gitops
# edit config/*.yaml, then:
git commit -am "update realm" && git push origin main
kubectl -n argocd annotate application keycloak-k8store argocd.argoproj.io/refresh=hard --overwrite
```

The Application uses automated sync with self-heal, so a manual `kubectl` edit inside `kc-argocd` is
reverted to match git. In a real setup ArgoCD points at your own remote (for example this repo on
GitHub) and you just commit to `scenarios/08-argocd/app/` and push there. The in-cluster git server is a
self-contained stand-in so the demo needs no external repo. Its repo is ephemeral (a pod restart
resets it to the baked seed).
