// Reads a kubectl `-o json` List on stdin and emits clean multi-document YAML on
// stdout, one document per item, with server-populated metadata and status removed.
// Used to turn CRs that k8store materialized in write mode into committable GitOps config.
import { dump } from "js-yaml";

// namespace is deliberately dropped so the CRs are portable across scenario namespaces
// (deploy.sh applies them with an explicit -n).
const KEEP_META = ["name", "labels", "annotations"];

const raw = await new Promise((resolve) => {
  let buf = "";
  process.stdin.on("data", (d) => (buf += d));
  process.stdin.on("end", () => resolve(buf));
});

const list = JSON.parse(raw);
const items = (list.items || [list]).sort((a, b) =>
  a.metadata.name.localeCompare(b.metadata.name),
);

const docs = items.map((it) => {
  const meta = {};
  for (const k of KEEP_META) if (it.metadata[k] !== undefined) meta[k] = it.metadata[k];
  if (meta.annotations) delete meta.annotations["kubectl.kubernetes.io/last-applied-configuration"];
  if (meta.annotations && Object.keys(meta.annotations).length === 0) delete meta.annotations;
  return {
    apiVersion: it.apiVersion,
    kind: it.kind,
    metadata: meta,
    spec: it.spec,
  };
});

process.stdout.write(
  docs.map((d) => dump(d, { lineWidth: 120, noRefs: true })).join("---\n"),
);
