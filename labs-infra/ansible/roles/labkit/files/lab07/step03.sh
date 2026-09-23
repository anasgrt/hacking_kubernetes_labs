#!/usr/bin/env bash
# Extracted from theory.md — Lab 7, command block 3.
# Read before running; some blocks expect variables set by earlier blocks.

# Valid object in the enforced namespace: should pass.
k create -n hk-lab07 --dry-run=server -f 07-pod.yaml

# Missing label in the enforced namespace: should be denied.
sed '/    costcenter: training/d' 07-pod.yaml \
  | k create -n hk-lab07 --dry-run=server -f -

# Same missing label outside the binding: should pass.
sed '/    costcenter: training/d' 07-pod.yaml \
  | k create -n hk-lab07-control --dry-run=server -f -
