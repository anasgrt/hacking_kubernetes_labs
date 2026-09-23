#!/usr/bin/env bash
# Extracted from theory.md — Lab 7, command block 2.
# Read before running; some blocks expect variables set by earlier blocks.

k apply -f 07-policy.yaml -f 07-binding.yaml
k get validatingadmissionpolicy hk-lab07-costcenter -o yaml
