#!/usr/bin/env bash
# Extracted from theory.md — Lab 5, command block 4.
# Read before running; some blocks expect variables set by earlier blocks.

k delete pod secret-reader -n hk-lab05 --wait=true
k apply -n hk-lab05 -f 05-reader.yaml
k wait -n hk-lab05 --for=condition=Ready pod/secret-reader --timeout=120s
k exec -n hk-lab05 secret-reader -- python -c \
  'import os; print(os.environ["DUMMY_PASSWORD"])'
