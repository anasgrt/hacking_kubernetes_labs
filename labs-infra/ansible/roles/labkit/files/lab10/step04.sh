#!/usr/bin/env bash
# Extracted from theory.md — Lab 10, command block 4.
# Read before running; some blocks expect variables set by earlier blocks.

mkdir -p evidence-lab10
k logs -n "${FALCO_NS:?Run sensor discovery first}" "${FALCO_POD:?Run sensor discovery first}" \
  --all-containers=true --since=5m --tail=-1 --prefix=true \
  > evidence-lab10/falco.log

grep -F 'hk-lab10' evidence-lab10/falco.log
k get pod observed -n hk-lab10 -o yaml > evidence-lab10/pod.yaml
k get events -n hk-lab10 --sort-by=.metadata.creationTimestamp \
  > evidence-lab10/events.txt

python3 - <<'PYCODE'
from pathlib import Path
import hashlib
for path in sorted(Path("evidence-lab10").glob("*")):
    if path.is_file():
        print(hashlib.sha256(path.read_bytes()).hexdigest(), path.name)
PYCODE
