#!/usr/bin/env bash
# Extracted from theory.md — Lab 0, command block 3.
# Read before running; some blocks expect variables set by earlier blocks.

new_lab() {
  local namespace="$1"
  k create namespace "$namespace" || return 1
  k label namespace "$namespace" \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/enforce-version=v1.30 || return 1
}
