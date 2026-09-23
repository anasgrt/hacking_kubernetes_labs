#!/usr/bin/env bash
# Extracted from theory.md — Lab 1, command block 4.
# Read before running; some blocks expect variables set by earlier blocks.

k exec -n hk-lab01 readonly -- sh -c \
  "awk '/^(CapEff|NoNewPrivs|Seccomp):/' /proc/self/status"
