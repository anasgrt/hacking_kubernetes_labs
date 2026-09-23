#!/usr/bin/env bash
# Extracted from theory.md — Lab 8, command block 4.
# Read before running; some blocks expect variables set by earlier blocks.

k delete pod first -n hk-lab08 --wait=true
k describe resourcequota one-pod -n hk-lab08
sed 's/name: first/name: second/' 08-first.yaml \
  | k create -n hk-lab08 -f -
k wait -n hk-lab08 --for=condition=Ready pod/second --timeout=120s
