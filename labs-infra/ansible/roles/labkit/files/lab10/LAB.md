# Lab 10 — Follow a harmless shell event into Falco

Extracted verbatim from theory.md. Do not edit here; edit theory.md
and re-run bin/extract-labs.py.

**Related:** Chapter 9 and Appendix A. **Objective:** validate the complete sensor-to-alert path and preserve a small evidence bundle before deleting the workload.

**Conditional lab:** Falco must already be healthy on the worker that runs this Pod, with the terminal-shell rule enabled and output accessible through Pod logs. Other output backends require checking the equivalent alert destination. This lab does not install a privileged sensor or change cluster audit configuration.

#### 1. Locate the sensor and start the observed workload

```bash
k get pods -A -l app.kubernetes.io/name=falco -o wide
new_lab hk-lab10
```

Save as `10-observed.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: observed
  labels:
    lab: '10'
    app: observed
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: docker.io/library/python:3.13-slim@sha256:8d9d0b8bcf6506481eae4907c18f5e3e7902e629f5f6d684f9e7c32e85e3ddf0
      command:
        - python
        - -c
        - import time; time.sleep(3600)
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 500m
          memory: 128Mi
      volumeMounts:
        - name: scratch
          mountPath: /tmp
  volumes:
    - name: scratch
      emptyDir:
        sizeLimit: 32Mi
```

```bash
k apply -n hk-lab10 -f 10-observed.yaml
k wait -n hk-lab10 --for=condition=Ready pod/observed --timeout=120s
k get pod observed -n hk-lab10 -o wide
WORKLOAD_NODE="$(k get pod observed -n hk-lab10 -o jsonpath='{.spec.nodeName}')"
FALCO_SENSOR="$(k get pods -A -l app.kubernetes.io/name=falco -o json |
  python3 -c 'import json, sys
node = sys.argv[1]
pods = json.load(sys.stdin)["items"]
ready = [p for p in pods if p.get("spec", {}).get("nodeName") == node
         and any(c.get("type") == "Ready" and c.get("status") == "True"
                 for c in p.get("status", {}).get("conditions", []))]
if len(ready) != 1:
    raise SystemExit("Expected exactly one Ready Falco Pod on the workload node; inspect the sensor installation before continuing")
p = ready[0]
print(p["metadata"]["namespace"], p["metadata"]["name"])
' "$WORKLOAD_NODE")"
read -r FALCO_NS FALCO_POD <<< "$FALCO_SENSOR"
printf 'Workload node: %s; sensor: %s/%s\n' "$WORKLOAD_NODE" "$FALCO_NS" "$FALCO_POD"
```

**Checkpoint:** discovery must return one Ready Falco Pod on the workload’s node. Stop if it reports an error or empty names. The standard Falco installation label is used; a custom installation with different labels must be identified by its owner before continuing.

#### 2. Trigger one terminal shell

Run from an interactive terminal so `-t` can allocate a terminal. The command prints identity and exits; it does not install packages, read credentials, or change host state.

```bash
k exec -it -n hk-lab10 observed -- sh -c 'id; printf "hk-lab10-marker\n"'
```

#### 3. Collect the alert and workload context

```bash
mkdir -p evidence-lab10
k logs -n "${FALCO_NS:?Run sensor discovery first}" "${FALCO_POD:?Run sensor discovery first}" \
  --all-containers=true --since=5m --tail=-1 --prefix=true \
  > evidence-lab10/falco.log

grep -F 'hk-lab10' evidence-lab10/falco.log
k get pod observed -n hk-lab10 -o yaml > evidence-lab10/pod.yaml
k get events -n hk-lab10 --sort-by=.metadata.creationTimestamp \
  > evidence-lab10/events.txt

python3 - <<'PYCODE'
from pathlib import Path
import hashlib
for path in sorted(Path("evidence-lab10").glob("*")):
    if path.is_file():
        print(hashlib.sha256(path.read_bytes()).hexdigest(), path.name)
PYCODE
```

**Expected:** an alert identifying a terminal shell in the `hk-lab10` workload, with process/container context. Capture its time, rule name, node, and workload identity. Alert text and fields depend on the installed rules/output configuration. The file hashes help detect later changes to the acquired files; they do not prove that the original source was uncompromised.

**Troubleshooting:** no match means the detection test has not passed. Check sensor placement, collection health/event drops, rule exceptions, terminal allocation, metadata enrichment, output destination, and log-access permissions. A shell printing its marker does not prove Falco observed it. Logs are collected only from the discovered sensor on this workload’s node.

#### 4. Clean up the workload; retain only appropriate evidence

```bash
k delete namespace hk-lab10
unset FALCO_NS FALCO_POD FALCO_SENSOR WORKLOAD_NODE
```

The captured sensor log may include other cluster metadata within the time window. Keep it in the lab’s controlled storage and do not publish it. The existing Falco installation remains unchanged. [Falco default rules](https://falco.org/docs/reference/rules/default-rules/)

**Pass criterion:** correlate one known shell action with one actual alert and its workload context. Record detection as unverified if no alert arrives; do not infer that no intrusion occurred.
