#!/usr/bin/env bash
# Extracted from theory.md — Lab 6, command block 2.
# Read before running; some blocks expect variables set by earlier blocks.

printf 'version-two\n' > version.txt
docker build -f Dockerfile.lab -t hk-study-local:current .
V2_ID="$(docker image inspect hk-study-local:current --format '{{.Id}}')"
printf 'v1: %s\nv2: %s\n' "$V1_ID" "$V2_ID"
test "$V1_ID" != "$V2_ID" && printf '%s\n' 'PASS: the tag now resolves to different content'
docker run --rm --network=none --read-only hk-study-local:current
docker run --rm --network=none --read-only hk-study-local:v1
