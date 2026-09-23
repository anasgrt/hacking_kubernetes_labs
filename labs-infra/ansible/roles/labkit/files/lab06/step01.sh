#!/usr/bin/env bash
# Extracted from theory.md — Lab 6, command block 1.
# Read before running; some blocks expect variables set by earlier blocks.

printf 'version-one\n' > version.txt
docker build -f Dockerfile.lab -t hk-study-local:current .
docker tag hk-study-local:current hk-study-local:v1
V1_ID="$(docker image inspect hk-study-local:v1 --format '{{.Id}}')"
docker run --rm --network=none --read-only hk-study-local:v1
