#!/usr/bin/env bash
# Extracted from theory.md — Lab 1, command block 3.
# Read before running; some blocks expect variables set by earlier blocks.

for pod in writable readonly; do
  printf '\nPod: %s\n' "$pod"
  k exec -i -n hk-lab01 "$pod" -- python - <<'PYCODE'
from pathlib import Path
import os
print(f"uid={os.getuid()} gid={os.getgid()}")
for target in ("/var/tmp/root-marker", "/tmp/scratch-marker"):
    try:
        Path(target).write_text("lab-only\n")
        print(f"WRITE_OK {target}")
    except OSError as exc:
        print(f"WRITE_DENIED {target}: errno={exc.errno} {exc.strerror}")
PYCODE
done
