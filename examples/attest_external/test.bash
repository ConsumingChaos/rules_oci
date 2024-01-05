#!/usr/bin/env bash
set -o pipefail -o errexit -o nounset

export HOME="$TEST_TMPDIR"

readonly COREUTILS="${1/external\//../}"
readonly JQ="${2/external\//../}"
readonly SED="${3/external\//../}"
readonly COSIGN="${4/external\//../}"
readonly CRANE="${5/external\//../}"
readonly REGISTRY_LAUNCHER="${6/external\//../}"
readonly ATTACHER="$7"
readonly IMAGE_PATH="$8"
readonly SBOM_PATH="$9"


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

# generate key
COSIGN_PASSWORD=123 "${COSIGN}" generate-key-pair

# due to https://github.com/sigstore/cosign/issues/2603 push the image
REF=$(mktemp)
"${CRANE}" push "${IMAGE_PATH}" "${REPOSITORY}" --image-refs="${REF}"

# attach the sbom
COSIGN_PASSWORD=123 "${ATTACHER}" --repository "${REPOSITORY}" --key=cosign.key -y

# download the sbom
"${COSIGN}" verify-attestation $(cat $REF) --key=cosign.pub --type spdx | "${JQ}" -r '.payload' | base64 --decode | "${JQ}" -r '.predicate' > "$TEST_TMPDIR/download.sbom"

diff -u --ignore-space-change --strip-trailing-cr "$SBOM_PATH"  "$TEST_TMPDIR/download.sbom" || (echo "FAIL: downloaded SBOM does not match the original" && exit 1)
