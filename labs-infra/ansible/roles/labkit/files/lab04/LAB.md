# Lab 4 — Verify NetworkPolicy with one allowed and one denied client

Extracted verbatim from theory.md. Do not edit here; edit theory.md
and re-run bin/extract-labs.py.

**Related:** Chapter 5. **Objective:** prove ingress selection and enforcement using a direct Pod IP. DNS, Service translation, and egress policy are deliberately excluded from this first comparison.

**Additional prerequisite:** a functioning policy-enforcing CNI, IPv4 Pod connectivity, and no unrelated cluster-wide policy blocking the baseline. These fixtures bind the server to `0.0.0.0` and use an IPv4 Pod address. On an IPv6-only cluster, both the server bind address and the client URL must be adapted; adding URL brackets alone is insufficient.

#### 1. Start the server and two clients

```bash
new_lab hk-lab04
```

Save as `04-api.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api
  labels:
    lab: '04'
    app: api
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
        - -m
        - http.server
        - '8080'
        - --bind
        - 0.0.0.0
        - --directory
        - /tmp
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
      ports:
        - containerPort: 8080
      readinessProbe:
        httpGet:
          path: /
          port: 8080
        initialDelaySeconds: 1
        periodSeconds: 2
  volumes:
    - name: scratch
      emptyDir:
        sizeLimit: 32Mi
```

Save as `04-client.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: client
  labels:
    lab: '04'
    app: client
    role: frontend
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

Save as `04-other.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: other
  labels:
    lab: '04'
    app: other
    role: other
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
k apply -n hk-lab04 -f 04-api.yaml
k apply -n hk-lab04 -f 04-client.yaml
k apply -n hk-lab04 -f 04-other.yaml
k wait -n hk-lab04 --for=condition=Ready pod/api pod/client pod/other --timeout=120s
API_IP="$(k get pod api -n hk-lab04 -o jsonpath='{.status.podIP}')"

probe_api() {
  k exec -n hk-lab04 "$1" -- python -c \
    'import sys, urllib.request; print(urllib.request.urlopen(sys.argv[1], timeout=3).status)' \
    "http://$API_IP:8080/"
}

probe_api client
probe_api other
```

**Baseline:** both return `200`. Stop and fix connectivity if either fails.

#### 2. Allow only the frontend label

Save as `04-policy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-ingress
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: frontend
      ports:
        - protocol: TCP
          port: 8080
```

```bash
k apply -n hk-lab04 -f 04-policy.yaml
probe_api client
probe_api other
```

**Expected after policy convergence:** `client` returns `200`; `other` fails within the client’s three-second timeout, or receives a network error depending on the CNI. Each invocation opens a new connection. If propagation is still in progress, repeat the same two probes after inspecting CNI status.

#### 3. Remove only the rule and retest

```bash
k delete networkpolicy api-ingress -n hk-lab04
probe_api other
```

**Expected:** `other` returns `200` again. This recovery comparison ties the change in connectivity to the policy rather than to an unrelated server failure.

**Troubleshooting:** both succeeding suggests absent enforcement, wrong labels, or another allowing policy. Both failing suggests a server, routing, or broader policy issue. Review `k get networkpolicy -n hk-lab04` and `k describe pod api -n hk-lab04`; use CNI flow/drop evidence if available.

#### 4. Clean up

```bash
k delete namespace hk-lab04
unset API_IP
unset -f probe_api
```

**Pass criterion:** record the result matrix: before `200/200`, after `200/blocked`, after removal `200/200`. This policy protects ingress to `api`; it is not a namespace-wide egress control. [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
