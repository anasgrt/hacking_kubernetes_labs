#!/usr/bin/env bash
# Extracted from theory.md — Lab 1, command block 2.
# Read before running; some blocks expect variables set by earlier blocks.

k apply -n hk-lab01 -f 01-writable.yaml
k apply -n hk-lab01 -f 01-readonly.yaml
k wait -n hk-lab01 --for=condition=Ready pod/writable pod/readonly --timeout=120s
