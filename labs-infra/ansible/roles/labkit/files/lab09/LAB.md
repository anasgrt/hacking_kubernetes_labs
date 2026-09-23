# Lab 9 — Verify an installed sandbox runtime

Extracted verbatim from theory.md. Do not edit here; edit theory.md
and re-run bin/extract-labs.py.

**Related:** Chapter 3. **Objective:** distinguish selecting a RuntimeClass from actually installing and using its handler.

**Conditional lab:** run only where a supported sandbox such as gVisor or Kata is already configured on compatible nodes. This workbook does not install runtimes or change node services. If none exists, record this lab as unavailable rather than inventing a handler name.

### 1. Inspect the configured class

```bash
k get runtimeclasses
RUNTIME_CLASSES=()
while IFS= read -r runtime_class; do
  RUNTIME_CLASSES+=("$runtime_class")
done < <(k get runtimeclasses -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
unset LAB_RUNTIME_CLASS
PS3='Select the installed sandbox class by number: '
select LAB_RUNTIME_CLASS in "${RUNTIME_CLASSES[@]}"; do
  if [ -n "$LAB_RUNTIME_CLASS" ]; then
    k get runtimeclass "$LAB_RUNTIME_CLASS" -o yaml
    break
  fi
  printf '%s\n' 'Choose one of the listed numbers.' >&2
done
```

If the list is empty, stop this conditional lab. Choose a class backed by gVisor or Kata, not an ordinary runc handler. Inspect `handler`, scheduling selectors/tolerations, and configured overhead. Confirm with the platform owner that the corresponding CRI handler exists on eligible nodes. A RuntimeClass object by itself is insufficient evidence.

### 2. Launch the bounded test

The following base file is complete YAML. The local patch command inserts the actual class selected above and writes `09-sandbox-selected.yaml`; that resulting file is the one created in the cluster. Do not apply the base file by itself.

```bash
new_lab hk-lab09
```

Save as `09-sandbox.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sandbox-check
  labels:
    lab: '09'
    app: sandbox-check
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
k patch --local -f 09-sandbox.yaml --type=merge \
  -p "{\"spec\":{\"runtimeClassName\":\"${LAB_RUNTIME_CLASS:?Select an installed sandbox class first}\"}}" \
  -o yaml > 09-sandbox-selected.yaml
k create -n hk-lab09 -f 09-sandbox-selected.yaml
k wait -n hk-lab09 --for=condition=Ready pod/sandbox-check --timeout=180s
k get pod sandbox-check -n hk-lab09 \
  -o jsonpath='{.spec.runtimeClassName}{"\n"}{.spec.nodeName}{"\n"}{.status.containerStatuses[0].containerID}{"\n"}'
k exec -n hk-lab09 sandbox-check -- python -c \
  'import os, platform; print("uid:", os.getuid()); print("kernel view:", platform.release())'
```

**Expected:** the Pod runs and reports the selected class and node. The process runs as UID 10001. Kernel strings and container ID prefixes are useful context, but neither universally proves gVisor or Kata. Obtain node/runtime launch evidence for the specific container through your platform’s supported diagnostic interface before claiming the handler was verified.

**Troubleshooting:** `FailedCreatePodSandBox` can indicate a missing handler; Pending can indicate no eligible node; application errors can indicate sandbox incompatibility. Do not remove the requested class just to obtain a green result.

### 3. Clean up

```bash
k delete namespace hk-lab09
unset LAB_RUNTIME_CLASS
```

**Pass criterion:** a running Pod plus supporting runtime evidence. Without that evidence, record “configuration requested; implementation unverified.” Do not run breakout payloads to test the sandbox.
