# Lab 5 — Compare Secret files with environment variables

Extracted verbatim from theory.md. Do not edit here; edit theory.md
and re-run bin/extract-labs.py.

**Related:** Chapter 6. **Objective:** observe rotation behavior using dummy values. The file is mounted normally, not with `subPath`.

#### 1. Create the first value and its consumer

```bash
new_lab hk-lab05
k create secret generic rotation-demo -n hk-lab05 --from-literal=password=version-one
```

Save as `05-reader.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-reader
  labels:
    lab: '05'
    app: secret-reader
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
        - name: secret
          mountPath: /dummy
          readOnly: true
      env:
        - name: DUMMY_PASSWORD
          valueFrom:
            secretKeyRef:
              name: rotation-demo
              key: password
  volumes:
    - name: scratch
      emptyDir:
        sizeLimit: 32Mi
    - name: secret
      secret:
        secretName: rotation-demo
        defaultMode: 0444
```

`defaultMode: 0444` makes a readable dummy projection for this single-container experiment. Production permissions should be narrower where the consuming UID/GID model permits.

```bash
k apply -n hk-lab05 -f 05-reader.yaml
k wait -n hk-lab05 --for=condition=Ready pod/secret-reader --timeout=120s
k exec -n hk-lab05 secret-reader -- python -c \
  'import os; from pathlib import Path; print("env:", os.environ["DUMMY_PASSWORD"]); print("file:", Path("/dummy/password").read_text())'
```

**Expected:** both values are `version-one`.

#### 2. Rotate the Secret and observe a bounded wait

```bash
k create secret generic rotation-demo -n hk-lab05 \
  --from-literal=password=version-two --dry-run=client -o yaml \
  | k apply -f -

k exec -i -n hk-lab05 secret-reader -- python - <<'PYCODE'
from pathlib import Path
import os, time
print("environment:", os.environ["DUMMY_PASSWORD"])
deadline = time.monotonic() + 180
while time.monotonic() < deadline:
    value = Path("/dummy/password").read_text()
    if value == "version-two":
        print("projected file:", value)
        break
    time.sleep(2)
else:
    raise SystemExit("Projection did not refresh within the observation window")
PYCODE
```

**Expected:** environment remains `version-one`; the file eventually becomes `version-two`. Projection is asynchronous, so the observation window is not a guaranteed Kubernetes refresh SLA. An application must reread/reload the file to use the new value.

#### 3. Recreate the consumer

```bash
k delete pod secret-reader -n hk-lab05 --wait=true
k apply -n hk-lab05 -f 05-reader.yaml
k wait -n hk-lab05 --for=condition=Ready pod/secret-reader --timeout=120s
k exec -n hk-lab05 secret-reader -- python -c \
  'import os; print(os.environ["DUMMY_PASSWORD"])'
```

**Expected:** the new process receives `version-two` in its environment.

**Troubleshooting:** a stale file requires checking whether the volume uses `subPath`, whether the Secret is immutable, and whether kubelet updates are healthy. A fresh file with stale application behavior indicates application reload behavior, not necessarily projection failure.

#### 4. Clean up

```bash
k delete namespace hk-lab05
```

**Pass criterion:** explain why updating an API object does not rewrite the environment of an existing container process. [Secret delivery](https://kubernetes.io/docs/concepts/configuration/secret/)
