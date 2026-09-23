# Lab 1 — Prove the Pod filesystem boundary

Extracted verbatim from theory.md. Do not edit here; edit theory.md
and re-run bin/extract-labs.py.

**Related:** Chapter 2. **Objective:** compare two otherwise identical nonroot Pods. One can write to its root mount; the other cannot. Both can use `/tmp`.

#### 1. Create the namespace and two Pods

```bash
new_lab hk-lab01
```

Save as `01-writable.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: writable
  labels:
    lab: '01'
    app: writable
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
        readOnlyRootFilesystem: false
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

Save as `01-readonly.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: readonly
  labels:
    lab: '01'
    app: readonly
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
k apply -n hk-lab01 -f 01-writable.yaml
k apply -n hk-lab01 -f 01-readonly.yaml
k wait -n hk-lab01 --for=condition=Ready pod/writable pod/readonly --timeout=120s
```

#### 2. Run the same write test in both Pods

`/var/tmp` is normally world-writable in this image and is part of the root mount. `/tmp` is the explicit writable volume. This avoids confusing a UID permission denial with a read-only mount.

```bash
for pod in writable readonly; do
  printf '\nPod: %s\n' "$pod"
  k exec -i -n hk-lab01 "$pod" -- python - <<'PYCODE'
from pathlib import Path
import os
print(f"uid={os.getuid()} gid={os.getgid()}")
for target in ("/var/tmp/root-marker", "/tmp/scratch-marker"):
    try:
        Path(target).write_text("lab-only\n")
        print(f"WRITE_OK {target}")
    except OSError as exc:
        print(f"WRITE_DENIED {target}: errno={exc.errno} {exc.strerror}")
PYCODE
done
```

**Expected evidence:** both report UID/GID 10001. `writable` succeeds on both paths. `readonly` reports errno 30 (`Read-only file system`) for `/var/tmp/root-marker` but succeeds on `/tmp/scratch-marker`.

#### 3. Inspect process restrictions

```bash
k exec -n hk-lab01 readonly -- sh -c \
  "awk '/^(CapEff|NoNewPrivs|Seccomp):/' /proc/self/status"
```

**Expected evidence:** effective capabilities are zero, `NoNewPrivs` is 1, and seccomp filter mode is 2 on a supporting Linux runtime. These observations establish specific restrictions; they do not prove the application cannot read its own credentials.

**Troubleshooting:** errno 13 is a filesystem permission failure, not the expected read-only result. Inspect the path’s ownership/mode. If the Pod fails to start, check `k describe pod readonly -n hk-lab01` before changing security settings.

#### 4. Clean up

```bash
k delete namespace hk-lab01
```

**Pass criterion:** explain why the read-only root does not prevent writes to `/tmp`. The separate volume is a separate writable mount.
