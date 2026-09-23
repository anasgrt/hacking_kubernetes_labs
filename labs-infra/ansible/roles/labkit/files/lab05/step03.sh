#!/usr/bin/env bash
# Extracted from theory.md — Lab 5, command block 3.
# Read before running; some blocks expect variables set by earlier blocks.

k create secret generic rotation-demo -n hk-lab05 \
  --from-literal=password=version-two --dry-run=client -o yaml \
  | k apply -f -

k exec -i -n hk-lab05 secret-reader -- python - <<'PYCODE'
from pathlib import Path
import os, time
print("environment:", os.environ["DUMMY_PASSWORD"])
deadline = time.monotonic() + 180
while time.monotonic() < deadline:
    value = Path("/dummy/password").read_text()
    if value == "version-two":
        print("projected file:", value)
        break
    time.sleep(2)
else:
    raise SystemExit("Projection did not refresh within the observation window")
PYCODE
