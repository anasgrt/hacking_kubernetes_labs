# Lab 7 — Enforce a scoped native CEL policy

Extracted verbatim from theory.md. Do not edit here; edit theory.md
and re-run bin/extract-labs.py.

**Related:** Chapter 8. **Objective:** show that a policy plus binding rejects a missing label in one namespace while leaving another namespace outside its scope.

**Additional prerequisite:** Kubernetes 1.30+ with the v1 ValidatingAdmissionPolicy API enabled and operator permission to create its cluster-scoped objects. Check that the two `hk-lab07-costcenter` objects do not already belong to another exercise before applying.

#### 1. Prepare both namespaces and the policy

```bash
new_lab hk-lab07
new_lab hk-lab07-control
k api-resources --api-group=admissionregistration.k8s.io
```

Save as `07-policy.yaml`:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: hk-lab07-costcenter
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups:
          - ''
        apiVersions:
          - v1
        operations:
          - CREATE
          - UPDATE
        resources:
          - pods
  validations:
    - expression: >-
        has(object.metadata.labels) && 'costcenter' in object.metadata.labels && object.metadata.labels['costcenter']
        != ''
      message: costcenter must be nonempty
```

Save as `07-binding.yaml`:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: hk-lab07-costcenter
spec:
  policyName: hk-lab07-costcenter
  validationActions:
    - Deny
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: hk-lab07
```

Save as `07-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: label-check
  labels:
    lab: '07'
    app: label-check
    costcenter: training
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
k apply -f 07-policy.yaml -f 07-binding.yaml
k get validatingadmissionpolicy hk-lab07-costcenter -o yaml
```

**Checkpoint:** inspect status/type-checking warnings. The API server loads new policies asynchronously; acceptance of the policy object alone is not proof of enforcement.

#### 2. Compare valid, invalid, and out-of-scope requests

```bash
# Valid object in the enforced namespace: should pass.
k create -n hk-lab07 --dry-run=server -f 07-pod.yaml

# Missing label in the enforced namespace: should be denied.
sed '/    costcenter: training/d' 07-pod.yaml \
  | k create -n hk-lab07 --dry-run=server -f -

# Same missing label outside the binding: should pass.
sed '/    costcenter: training/d' 07-pod.yaml \
  | k create -n hk-lab07-control --dry-run=server -f -
```

**Expected:** pass → policy denial mentioning `costcenter` → pass. All are dry-runs; no workload starts. If the negative test passes immediately after installation, inspect status and repeat after convergence; do not count it as success.

**Troubleshooting:** all passing means the binding/scope/evaluation is ineffective. Both namespaces denying means another policy also matches or the scope is wrong. A Pod Security error is a different control from this costcenter rule.

#### 3. Clean up both the activation and its definition

```bash
k delete validatingadmissionpolicybinding hk-lab07-costcenter
k delete validatingadmissionpolicy hk-lab07-costcenter
k delete namespace hk-lab07 hk-lab07-control
```

**Pass criterion:** explain why a validation policy without an applicable binding does not enforce this rule. [Native admission policy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)
