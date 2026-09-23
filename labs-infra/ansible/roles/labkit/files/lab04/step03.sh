#!/usr/bin/env bash
# Extracted from theory.md — Lab 4, command block 3.
# Read before running; some blocks expect variables set by earlier blocks.

k apply -n hk-lab04 -f 04-policy.yaml
probe_api client
probe_api other
