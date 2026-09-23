#!/usr/bin/env bash
# Extracted from theory.md — Lab 0, command block 1.
# Read before running; some blocks expect variables set by earlier blocks.

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
