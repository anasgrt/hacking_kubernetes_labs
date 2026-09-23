# Lab 6 — Demonstrate why image tags are not immutable identities

Extracted verbatim from theory.md. Do not edit here; edit theory.md
and re-run bin/extract-labs.py.

**Related:** Chapter 4. **Objective:** build two harmless local images under one tag and prove that the tag moves. No registry push or cluster change occurs.

**Prerequisite:** the Docker engine checked in Lab 0. The fixed local names below must be unused; choose a different prefix throughout this lab if they already contain your own work.

#### 1. Create a minimal image recipe

Save as `Dockerfile.lab`:

```docker
FROM docker.io/library/python:3.13-slim@sha256:8d9d0b8bcf6506481eae4907c18f5e3e7902e629f5f6d684f9e7c32e85e3ddf0
WORKDIR /opt/lab
COPY version.txt /opt/lab/version.txt
USER 10001:10001
CMD ["python", "-c", "from pathlib import Path; print(Path('/opt/lab/version.txt').read_text().strip())"]
```

#### 2. Build and retain the first artifact

```bash
printf 'version-one\n' > version.txt
docker build -f Dockerfile.lab -t hk-study-local:current .
docker tag hk-study-local:current hk-study-local:v1
V1_ID="$(docker image inspect hk-study-local:v1 --format '{{.Id}}')"
docker run --rm --network=none --read-only hk-study-local:v1
```

**Expected:** `version-one`. `V1_ID` is a local image configuration digest; it is not interchangeable with the registry manifest/index digest used in a Kubernetes image reference.

#### 3. Move the tag to changed content

```bash
printf 'version-two\n' > version.txt
docker build -f Dockerfile.lab -t hk-study-local:current .
V2_ID="$(docker image inspect hk-study-local:current --format '{{.Id}}')"
printf 'v1: %s\nv2: %s\n' "$V1_ID" "$V2_ID"
test "$V1_ID" != "$V2_ID" && printf '%s\n' 'PASS: the tag now resolves to different content'
docker run --rm --network=none --read-only hk-study-local:current
docker run --rm --network=none --read-only hk-study-local:v1
```

**Expected:** different IDs; `current` prints `version-two`; `v1` still prints `version-one`.

**Interpretation:** a familiar tag can refer to different bytes. Pin deployed registry digests and separately verify producer/build evidence. This experiment proves mutability, not that either image is vulnerable or malicious. It does not substitute for SBOM or signature verification.

#### 4. Clean up the two lab image tags

```bash
docker image rm hk-study-local:current hk-study-local:v1
unset V1_ID V2_ID
```

Keep the small source files if you want to repeat the lab. The shared base image and build cache remain; do not use a broad Docker prune as workbook cleanup.

**Troubleshooting:** identical IDs mean the build did not consume the changed file; inspect `version.txt`, the build context, and `.dockerignore`. A build failure should be diagnosed from its log before disabling build protections.

**Pass criterion:** distinguish a tag, a local image ID, a registry manifest digest, and a signature.
