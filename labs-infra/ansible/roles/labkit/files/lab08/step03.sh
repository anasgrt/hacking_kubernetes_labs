#!/usr/bin/env bash
# Extracted from theory.md — Lab 8, command block 3.
# Read before running; some blocks expect variables set by earlier blocks.

sed 's/name: first/name: second/' 08-first.yaml \
  | k create -n hk-lab08 -f -
k get pods -n hk-lab08
