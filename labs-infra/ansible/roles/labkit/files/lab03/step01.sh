#!/usr/bin/env bash
# Extracted from theory.md — Lab 3, command block 1.
# Read before running; some blocks expect variables set by earlier blocks.

new_lab hk-lab03
k create serviceaccount pod-creator -n hk-lab03
k create secret generic dummy-db -n hk-lab03 \
  --from-literal=password=LAB-ONLY-NOT-A-CREDENTIAL
