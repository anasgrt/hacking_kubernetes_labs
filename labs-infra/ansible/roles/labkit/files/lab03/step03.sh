#!/usr/bin/env bash
# Extracted from theory.md — Lab 3, command block 3.
# Read before running; some blocks expect variables set by earlier blocks.

k create -n hk-lab03 --as="$LAB_SA" -f 03-reader.yaml

k wait -n hk-lab03 --for=jsonpath='{.status.phase}'=Succeeded \
  pod/indirect-reader --timeout=120s
k logs -n hk-lab03 indirect-reader
