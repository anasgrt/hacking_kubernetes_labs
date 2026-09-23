# Lab 2 — Reject an unsafe Pod before it runs

Extracted verbatim from theory.md. Do not edit here; edit theory.md
and re-run bin/extract-labs.py.

**Related:** Chapters 2 and 8. **Objective:** distinguish API admission from runtime enforcement. The unsafe variant is tested with server-side dry-run and is never persisted.

#### 1. Prepare the namespace and valid manifest

```bash
new_lab hk-lab02
```

Save as `02-valid.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: admission-check
  labels:
    lab: '02'
    app: admission-check
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

#### 2. Check the valid request

```bash
k create -n hk-lab02 --dry-run=server -f 02-valid.yaml
```

**Expected:** `pod/admission-check created (server dry run)`. No Pod is stored.

#### 3. Change exactly one field and repeat

```bash
sed 's/runAsNonRoot: true/runAsNonRoot: false/' 02-valid.yaml \
  | k create -n hk-lab02 --dry-run=server -f -

k get pods -n hk-lab02
```

**Expected:** a nonzero command result naming a Restricted Pod Security violation; the namespace remains empty. The positive test must have passed first, otherwise the negative result could be an unrelated schema or authorization error.

**Troubleshooting:** if the unsafe request passes, inspect namespace labels, admission exemptions, and the identity used. A privileged administrative exemption can invalidate this comparison. Stop; do not turn the dry-run into a real creation attempt.

#### 4. Clean up

```bash
k delete namespace hk-lab02
```

**Pass criterion:** identify which field was rejected and explain why no runtime experiment occurred. [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
