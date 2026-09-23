#!/usr/bin/env bash
# Extracted from theory.md — Lab 2, command block 3.
# Read before running; some blocks expect variables set by earlier blocks.

sed 's/runAsNonRoot: true/runAsNonRoot: false/' 02-valid.yaml \
  | k create -n hk-lab02 --dry-run=server -f -

k get pods -n hk-lab02
