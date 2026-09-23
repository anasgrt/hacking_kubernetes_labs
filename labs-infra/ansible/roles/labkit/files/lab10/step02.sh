#!/usr/bin/env bash
# Extracted from theory.md — Lab 10, command block 2.
# Read before running; some blocks expect variables set by earlier blocks.

k apply -n hk-lab10 -f 10-observed.yaml
k wait -n hk-lab10 --for=condition=Ready pod/observed --timeout=120s
k get pod observed -n hk-lab10 -o wide
WORKLOAD_NODE="$(k get pod observed -n hk-lab10 -o jsonpath='{.spec.nodeName}')"
FALCO_SENSOR="$(k get pods -A -l app.kubernetes.io/name=falco -o json |
  python3 -c 'import json, sys
node = sys.argv[1]
pods = json.load(sys.stdin)["items"]
ready = [p for p in pods if p.get("spec", {}).get("nodeName") == node
         and any(c.get("type") == "Ready" and c.get("status") == "True"
                 for c in p.get("status", {}).get("conditions", []))]
if len(ready) != 1:
    raise SystemExit("Expected exactly one Ready Falco Pod on the workload node; inspect the sensor installation before continuing")
p = ready[0]
print(p["metadata"]["namespace"], p["metadata"]["name"])
' "$WORKLOAD_NODE")"
read -r FALCO_NS FALCO_POD <<< "$FALCO_SENSOR"
printf 'Workload node: %s; sensor: %s/%s\n' "$WORKLOAD_NODE" "$FALCO_NS" "$FALCO_POD"
