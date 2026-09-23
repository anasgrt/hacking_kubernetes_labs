#!/usr/bin/env bash
# Extracted from theory.md — Lab 4, command block 4.
# Read before running; some blocks expect variables set by earlier blocks.

k delete networkpolicy api-ingress -n hk-lab04
probe_api other
