#!/usr/bin/env bash
# Extracted from theory.md — Lab 5, command block 2.
# Read before running; some blocks expect variables set by earlier blocks.

k apply -n hk-lab05 -f 05-reader.yaml
k wait -n hk-lab05 --for=condition=Ready pod/secret-reader --timeout=120s
k exec -n hk-lab05 secret-reader -- python -c \
  'import os; from pathlib import Path; print("env:", os.environ["DUMMY_PASSWORD"]); print("file:", Path("/dummy/password").read_text())'
