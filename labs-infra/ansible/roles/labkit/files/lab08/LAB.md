# Lab 8 — Distinguish quota rejection from scheduling failure

Extracted verbatim from theory.md. Do not edit here; edit theory.md
and re-run bin/extract-labs.py.

**Related:** Chapters 7 and 8. **Objective:** exceed a one-Pod namespace quota without generating CPU or memory pressure.

#### 1. Create the budget and first Pod

```bash
new_lab hk-lab08
```

Save as `08-quota.yaml`:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: one-pod
spec:
  hard:
    pods: '1'
    requests.cpu: 100m
    requests.memory: 128Mi
```

Save as `08-first.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: first
  labels:
    lab: '08'
    app: first
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
k apply -n hk-lab08 -f 08-quota.yaml
k apply -n hk-lab08 -f 08-first.yaml
k wait -n hk-lab08 --for=condition=Ready pod/first --timeout=120s
k describe resourcequota one-pod -n hk-lab08
```

#### 2. Request a second Pod

```bash
sed 's/name: first/name: second/' 08-first.yaml \
  | k create -n hk-lab08 -f -
k get pods -n hk-lab08
```

**Expected:** admission rejects the second Pod with an exceeded-quota message; only `first` exists. This is different from a stored Pod whose phase is Pending because no suitable node is available. The CPU/memory requests fit the remaining numeric budget, but the Pod-count budget is already exhausted.

#### 3. Release the slot and repeat

```bash
k delete pod first -n hk-lab08 --wait=true
k describe resourcequota one-pod -n hk-lab08
sed 's/name: first/name: second/' 08-first.yaml \
  | k create -n hk-lab08 -f -
k wait -n hk-lab08 --for=condition=Ready pod/second --timeout=120s
```

**Expected:** after quota accounting updates, `second` is admitted and runs. If quota usage has not refreshed, wait for the displayed usage to drop before repeating.

#### 4. Clean up

```bash
k delete namespace hk-lab08
```

**Pass criterion:** describe quota as aggregate admission accounting, not a runtime stress test or guaranteed node reservation.
