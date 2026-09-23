#!/usr/bin/env bash
# Extracted from theory.md — Lab 9, command block 3.
# Read before running; some blocks expect variables set by earlier blocks.

k patch --local -f 09-sandbox.yaml --type=merge \
  -p "{\"spec\":{\"runtimeClassName\":\"${LAB_RUNTIME_CLASS:?Select an installed sandbox class first}\"}}" \
  -o yaml > 09-sandbox-selected.yaml
k create -n hk-lab09 -f 09-sandbox-selected.yaml
k wait -n hk-lab09 --for=condition=Ready pod/sandbox-check --timeout=180s
k get pod sandbox-check -n hk-lab09 \
  -o jsonpath='{.spec.runtimeClassName}{"\n"}{.spec.nodeName}{"\n"}{.status.containerStatuses[0].containerID}{"\n"}'
k exec -n hk-lab09 sandbox-check -- python -c \
  'import os, platform; print("uid:", os.getuid()); print("kernel view:", platform.release())'
