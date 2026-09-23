#!/usr/bin/env bash
# Extracted from theory.md — Lab 8, command block 2.
# Read before running; some blocks expect variables set by earlier blocks.

k apply -n hk-lab08 -f 08-quota.yaml
k apply -n hk-lab08 -f 08-first.yaml
k wait -n hk-lab08 --for=condition=Ready pod/first --timeout=120s
k describe resourcequota one-pod -n hk-lab08
