# ArgoCD demo (real GitOps)

The `--preconfigured` scenarios apply their config with a script. This demo shows the same k8store +
PostgreSQL setup driven by **ArgoCD** instead, the way you would run it in production. ArgoCD watches
a git repo and reconciles the cluster to match it.

It is one combined demo (not a per-scenario variant). It uses the k8store + PostgreSQL setup
(scenario 3) as the example, because there ArgoCD actually syncs the config CRs.

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
kind/kind-up.sh          # once
argocd/setup.sh          # installs ArgoCD + git server, creates the Application, waits for Healthy

CNK_KC_SVC=keycloak test/verify.sh kc-argocd demo demo-app   # REST + browser login + clients page
# or open http://localhost:8080 (admin/admin)

argocd/teardown.sh       # remove the demo
```

The Keycloak image is scenario 3's (`localhost:5001/cnk-03:dev`). `setup.sh` builds it if missing.
ArgoCD only syncs manifests, so in a real setup CI builds the image and ArgoCD references it.

## ArgoCD UI

The `argocd-server` Service is ClusterIP (the kind host ports are used by Keycloak). Reach the UI
with a port-forward:

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:443
# open https://localhost:8081 (accept the self-signed cert), user: admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

The password comes from the `argocd-initial-admin-secret` that ArgoCD creates on install.

## Changing config the GitOps way

Edit a CR under `app/config/`, rebuild and push the git-server image (or push a commit to the repo),
and ArgoCD reconciles the change. The Application uses automated sync with self-heal, so a manual
`kubectl` edit inside `kc-argocd` is reverted to match git.
