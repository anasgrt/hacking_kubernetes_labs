#!/usr/bin/env bash
# Extracted from theory.md — Lab 10, command block 1.
# Read before running; some blocks expect variables set by earlier blocks.

k get pods -A -l app.kubernetes.io/name=falco -o wide
new_lab hk-lab10
