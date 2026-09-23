# Lab 0 — Prepare a disposable environment

Extracted verbatim from theory.md. Do not edit here; edit theory.md
and re-run bin/extract-labs.py.

**Objective:** establish the prerequisites once and avoid accidental use of a production context.

**Required:** a disposable Kubernetes cluster with Linux workers and a currently supported Kubernetes release with the required APIs (1.30 is the historical minimum for these manifests, not a recommended release); a `kubectl` version supported for that server; Docker CLI with a running engine; local Python 3; and permission to create the lab namespaces and named resources. Labs 3 and 7 additionally require impersonation/RBAC and cluster-scoped policy permissions. Lab 4 requires a CNI that actually enforces NetworkPolicy. A default cluster that only stores NetworkPolicy objects is insufficient. Labs 9 and 10 are conditional on existing runtime/sensor installations.

### 1. Start one Bash session and select the lab context

Run the remaining commands in this same Bash session. The wrapper always targets the context you selected, even if your global current context changes later.

```bash
bash
set -o pipefail
mkdir -p hacking-kubernetes-labs
cd hacking-kubernetes-labs || exit 1
kubectl config get-contexts
LAB_CONTEXTS=()
while IFS= read -r context; do
  LAB_CONTEXTS+=("$context")
done < <(kubectl config get-contexts -o name)
unset LAB_CONTEXT
PS3='Select the disposable cluster by number: '
select LAB_CONTEXT in "${LAB_CONTEXTS[@]}"; do
  if [ -n "$LAB_CONTEXT" ]; then
    export LAB_CONTEXT
    break
  fi
  printf '%s\n' 'Choose one of the listed numbers.' >&2
done

k() {
  if [ -z "${LAB_CONTEXT:-}" ]; then
    printf '%s\n' 'LAB_CONTEXT is empty; repeat Lab 0.' >&2
    return 1
  fi
  kubectl --context="$LAB_CONTEXT" "$@"
}

k cluster-info
k version
k get nodes -L kubernetes.io/os
```

**Checkpoint:** recognize the cluster endpoint and Linux nodes. Stop on an unexpected cluster or failed command. Do not concatenate the entire workbook into an unattended script; expected denials deliberately return nonzero exit codes.

### 2. Check the real image used throughout the labs

The manifests use the official Python 3.13 slim image pinned to the complete registry digest below. The registry index and its Linux amd64/arm64 configurations were checked on September 23, 2026; both configurations report Python 3.13.15. Python supplies the HTTP server, client, and file-inspection commands used in the exercises. No image editing or substitution is required. [Official Python image](https://hub.docker.com/_/python)

```bash
docker pull docker.io/library/python:3.13-slim@sha256:8d9d0b8bcf6506481eae4907c18f5e3e7902e629f5f6d684f9e7c32e85e3ddf0
docker run --rm --network=none --read-only \
  docker.io/library/python:3.13-slim@sha256:8d9d0b8bcf6506481eae4907c18f5e3e7902e629f5f6d684f9e7c32e85e3ddf0 \
  python --version
```

**Expected:** the pull succeeds and the container prints `Python 3.13.15`. Stop on a failed pull or unsupported platform. The cluster workers also need access to Docker Hub; pulling on your laptop does not populate their image caches. The digest fixes the artifact identity; it is not a claim that the image is vulnerability-free.

### 3. Define the namespace helper

`new_lab` refuses to reuse an existing namespace and applies the Restricted Pod Security Standard pinned to `v1.30` for the exercise baseline. Each manifest already contains its real image reference and is applied directly with `k apply` or `k create`.

```bash
new_lab() {
  local namespace="$1"
  k create namespace "$namespace" || return 1
  k label namespace "$namespace" \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/enforce-version=v1.30 || return 1
}
```

**Finish condition:** the context is selected, the image check passes, the helpers exist, and the cluster prerequisites are understood. Cluster labs create and remove their own named namespaces; Lab 6 uses only local Docker images. Lab 7 also creates and removes its two explicitly named cluster-scoped admission objects. If namespace creation reports `AlreadyExists`, stop and inspect it; do not delete it to force a clean start.

**Troubleshooting:** `ImagePullBackOff` is a registry/architecture/access issue, not proof of a policy denial. `Pending` requires inspecting events and scheduling constraints. A forbidden API request requires the specific lab permission; do not solve it by granting workload service accounts cluster-admin.
