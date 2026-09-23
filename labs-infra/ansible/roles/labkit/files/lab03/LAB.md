# Lab 3 — Demonstrate indirect Secret access through Pod creation

Extracted verbatim from theory.md. Do not edit here; edit theory.md
and re-run bin/extract-labs.py.

**Related:** Chapters 6 and 8. **Objective:** prove that denying direct Secret reads does not remove every path to Secret data. Use only the dummy string shown here.

**Additional prerequisite:** the operator may create namespaced RBAC and impersonate the lab service account. The created workload uses no API token and satisfies Restricted admission.

#### 1. Create the identity, dummy Secret, and narrow grant

```bash
new_lab hk-lab03
k create serviceaccount pod-creator -n hk-lab03
k create secret generic dummy-db -n hk-lab03 \
  --from-literal=password=LAB-ONLY-NOT-A-CREDENTIAL
```

Save as `03-role.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-creator
rules:
  - apiGroups:
      - ''
    resources:
      - pods
    verbs:
      - create
```

Save as `03-binding.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-creator
subjects:
  - kind: ServiceAccount
    name: pod-creator
    namespace: hk-lab03
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-creator
```

```bash
k apply -n hk-lab03 -f 03-role.yaml -f 03-binding.yaml
LAB_SA='system:serviceaccount:hk-lab03:pod-creator'
k auth can-i create pods -n hk-lab03 --as="$LAB_SA"
k auth can-i get secrets -n hk-lab03 --as="$LAB_SA"
```

**Expected:** `yes`, then `no`, assuming no other grants. `can-i` checks authorization; it does not test whether admission allows a particular Pod. Impersonating a service-account username alone may omit its group-based grants, so this exercise uses a direct ServiceAccount binding. Assess real credentials and groups when auditing production access.

#### 2. Create a Secret-reading Pod as that identity

Save as `03-reader.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: indirect-reader
  labels:
    lab: '03'
    app: indirect-reader
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
        - from pathlib import Path; print(Path("/dummy/password").read_text())
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
        - name: dummy
          mountPath: /dummy
          readOnly: true
  volumes:
    - name: scratch
      emptyDir:
        sizeLimit: 32Mi
    - name: dummy
      secret:
        secretName: dummy-db
```

```bash
k create -n hk-lab03 --as="$LAB_SA" -f 03-reader.yaml

k wait -n hk-lab03 --for=jsonpath='{.status.phase}'=Succeeded \
  pod/indirect-reader --timeout=120s
k logs -n hk-lab03 indirect-reader
```

**Expected:** the log contains `LAB-ONLY-NOT-A-CREDENTIAL`. The operator reads the logs for observation; the attacker-controlled process already accessed the data inside the Pod. Do not confuse the operator’s log permission with the workload’s mounted-file access.

**Why ****`create`****, not ****`apply`****?** This identity was granted only `create pods`. Client-side apply can require additional reads/patches. The explicit verb keeps the experiment aligned with its permission model.

#### 3. Explain the boundary and clean up

The kubelet delivers the referenced Secret to the authorized workload specification; direct Secret API permission was not required by the submitting identity. Additional admission restrictions could block this path, which is why “can create Pods” must be assessed with actual policies.

```bash
k delete namespace hk-lab03
unset LAB_SA
```

**Troubleshooting:** an impersonation denial means the operator cannot perform the test. An admission denial may be a valid additional defense. A Pod waiting on a missing Secret means the fixture is wrong. None is evidence that RBAC alone prevents this indirect path.

**Pass criterion:** distinguish direct API permission, permission to submit a workload, and the workload’s file access.
