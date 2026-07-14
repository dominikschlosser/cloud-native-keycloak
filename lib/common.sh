#!/usr/bin/env bash
# Shared helpers sourced by every scenario deploy.sh and by test/verify.sh.
# Assumes `set -euo pipefail` in the caller.

CNK_CLUSTER=cnk
CNK_CONTEXT="kind-${CNK_CLUSTER}"
CNK_REGISTRY=localhost:5001
KUBECTL="kubectl --context ${CNK_CONTEXT}"

# Repo root, regardless of where the caller lives.
CNK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

require_cluster() {
  kind get clusters 2>/dev/null | grep -qx "${CNK_CLUSTER}" \
    || die "kind cluster '${CNK_CLUSTER}' not found. Run kind/kind-up.sh first."
}

# apply_db <namespace> <postgres|cassandra> : render a shared DB manifest into the namespace
apply_db() {
  local ns="$1" kind="$2"
  sed "s/{{NAMESPACE}}/${ns}/g" "${CNK_ROOT}/lib/manifests/${kind}.yaml" | ${KUBECTL} apply -f -
}

# wait_rollout <namespace> <deployment|statefulset/name> <timeout>
wait_rollout() {
  local ns="$1" obj="$2" timeout="${3:-600s}"
  ${KUBECTL} -n "${ns}" rollout status "${obj}" --timeout="${timeout}"
}

# resolve_providers <outdir> <coord...> : stage extension jars plus their runtime
# dependencies into <outdir> using Maven. Each coord is groupId:artifactId:version.
# Handles both shaded jars (cassandra) and thin jars (k8store needs fabric8 at runtime).
resolve_providers() {
  local outdir="$1"; shift
  rm -rf "${outdir}"; mkdir -p "${outdir}"
  outdir="$(cd "${outdir}" && pwd)"
  local tmp; tmp="$(mktemp -d)"
  {
    echo '<project xmlns="http://maven.apache.org/POM/4.0.0">'
    echo '  <modelVersion>4.0.0</modelVersion>'
    echo '  <groupId>cnk</groupId><artifactId>providers</artifactId>'
    echo '  <version>1</version><packaging>pom</packaging>'
    echo '  <dependencies>'
    for coord in "$@"; do
      IFS=: read -r g a v <<<"${coord}"
      printf '    <dependency><groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version></dependency>\n' "$g" "$a" "$v"
    done
    echo '  </dependencies>'
    echo '</project>'
  } >"${tmp}/pom.xml"
  mvn -q -f "${tmp}/pom.xml" dependency:copy-dependencies \
    -DoutputDirectory="${outdir}" -DincludeScope=runtime
  rm -rf "${tmp}"
  log "Staged $(ls -1 "${outdir}" | wc -l | tr -d ' ') provider jars into ${outdir}"
}

# rest_smoke <base_url> : master realm answers 200 and admin/admin password grant works
rest_smoke() {
  local base="$1" status err
  log "REST smoke: GET ${base}/realms/master"
  status=000
  for _ in $(seq 1 30); do
    status=$(curl -s -o /dev/null -w '%{http_code}' "${base}/realms/master" || true)
    [ "${status}" = "200" ] && break
    sleep 2
  done
  [ "${status}" = "200" ] || die "smoke: /realms/master returned HTTP ${status}"
  err=$(curl -s -d 'client_id=admin-cli' -d 'username=admin' -d 'password=admin' \
    -d 'grant_type=password' "${base}/realms/master/protocol/openid-connect/token" \
    | (grep -o '"error_description":"[^"]*"' || true))
  [ -z "${err}" ] || die "smoke: admin login on master realm: ${err}"
  log "REST smoke OK: master realm reachable, admin/admin password grant works"
}
