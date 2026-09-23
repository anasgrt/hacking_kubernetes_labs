#!/usr/bin/env bash
# Extracted from theory.md — Lab 4, command block 2.
# Read before running; some blocks expect variables set by earlier blocks.

k apply -n hk-lab04 -f 04-api.yaml
k apply -n hk-lab04 -f 04-client.yaml
k apply -n hk-lab04 -f 04-other.yaml
k wait -n hk-lab04 --for=condition=Ready pod/api pod/client pod/other --timeout=120s
API_IP="$(k get pod api -n hk-lab04 -o jsonpath='{.status.podIP}')"

probe_api() {
  k exec -n hk-lab04 "$1" -- python -c \
    'import sys, urllib.request; print(urllib.request.urlopen(sys.argv[1], timeout=3).status)' \
    "http://$API_IP:8080/"
}

probe_api client
probe_api other
