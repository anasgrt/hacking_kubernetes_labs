#!/usr/bin/env bash
# Extracted from theory.md — Lab 7, command block 4.
# Read before running; some blocks expect variables set by earlier blocks.

k delete validatingadmissionpolicybinding hk-lab07-costcenter
k delete validatingadmissionpolicy hk-lab07-costcenter
k delete namespace hk-lab07 hk-lab07-control
