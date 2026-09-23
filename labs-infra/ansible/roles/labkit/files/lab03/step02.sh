#!/usr/bin/env bash
# Extracted from theory.md — Lab 3, command block 2.
# Read before running; some blocks expect variables set by earlier blocks.

k apply -n hk-lab03 -f 03-role.yaml -f 03-binding.yaml
LAB_SA='system:serviceaccount:hk-lab03:pod-creator'
k auth can-i create pods -n hk-lab03 --as="$LAB_SA"
k auth can-i get secrets -n hk-lab03 --as="$LAB_SA"
