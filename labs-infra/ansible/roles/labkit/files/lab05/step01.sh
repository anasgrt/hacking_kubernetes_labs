#!/usr/bin/env bash
# Extracted from theory.md — Lab 5, command block 1.
# Read before running; some blocks expect variables set by earlier blocks.

new_lab hk-lab05
k create secret generic rotation-demo -n hk-lab05 --from-literal=password=version-one
