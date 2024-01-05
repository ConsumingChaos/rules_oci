#!/usr/bin/env bash
set -o pipefail -o errexit -o nounset

export HOME="$TEST_TMPDIR"

readonly COREUTILS="${1/external\//../}"
readonly JQ="${2/external\//../}"
readonly SED="${3/external\//../}"
readonly CRANE="${4/external\//../}"
readonly COSIGN="${5/external\//../}"
readonly REGISTRY_LAUNCHER="${6/external\//../}"
readonly IMAGE_SIGNER="$7"
readonly IMAGE="$8"

# Launch a registry instance at a random port
export REGISTRY_BINARY="${CRANE}"
export REGISTRY_STORAGE_DIR="${TEST_TMPDIR}"
export COREUTILS
export SED
source "${REGISTRY_LAUNCHER}"

REGISTRY=$(start_registry)
trap "stop_registry" EXIT
echo "Registry is running at ${REGISTRY}"

readonly REPOSITORY="${REGISTRY}/local"
readonly DIGEST=$("$JQ" -r '.manifests[0].digest' "$IMAGE/index.json")

# TODO: make this test sign by digest once https://github.com/sigstore/cosign/issues/1905 is fixed.
"${CRANE}" push "${IMAGE}" "${REPOSITORY}@${DIGEST}"

# Create key-pair
COSIGN_PASSWORD=123 "${COSIGN}" generate-key-pair

# Sign the image at remote registry
echo "y" | COSIGN_PASSWORD=123 "${IMAGE_SIGNER}" --repository="${REPOSITORY}" --key=cosign.key

# Now push the image
REF=$(mktemp)
"${CRANE}" push "${IMAGE}" "${REPOSITORY}" --image-refs="${REF}"

# Verify using the Tag
"${COSIGN}" verify "${REPOSITORY}:latest" --key=cosign.pub

# Verify using the Digest
"${COSIGN}" verify "$(cat ${REF})" --key=cosign.pub
