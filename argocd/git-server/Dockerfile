# A minimal in-cluster git server. It seeds a repo from the app/ manifests at build time and
# serves it over the git:// protocol (read + push). ArgoCD syncs from git://git-server:9418/repo.
# Build context is the argocd/ directory.
FROM alpine:3.20
RUN apk add --no-cache git git-daemon
RUN mkdir -p /srv/repo
COPY app/ /srv/repo/
RUN cd /srv/repo \
    && git init -q -b main \
    && git add -A \
    && git -c user.email=argo@cnk -c user.name=cnk commit -qm "seed keycloak-k8store gitops app" \
    && git config receive.denyCurrentBranch updateInstead \
    && touch .git/git-daemon-export-ok
EXPOSE 9418
ENTRYPOINT ["git", "daemon", "--reuseaddr", "--base-path=/srv", "--export-all", "--enable=receive-pack", "--verbose", "/srv"]
