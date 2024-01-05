#!/usr/bin/env bash
set -o pipefail -o errexit -o nounset

readonly CRANE="${1/external\//../}"
readonly REGISTRY_LAUNCHER="${2/external\//../}"
readonly COREUTILS="${3/external\//../}"
readonly SED="${4/external\//../}"
readonly PUSH_IMAGE="$5"
readonly PUSH_IMAGE_INDEX="$6"
readonly PUSH_IMAGE_REPOSITORY_FILE="$7"
readonly PUSH_IMAGE_WO_TAGS="$8"

# Launch a registry instance at a random port
export REGISTRY_BINARY="${CRANE}"
export REGISTRY_STORAGE_DIR="${TEST_TMPDIR}"
export COREUTILS
export SED
source "${REGISTRY_LAUNCHER}"

REGISTRY=$(start_registry)
trap "stop_registry" EXIT
echo "Registry is running at ${REGISTRY}"

# should push image with default tags
REPOSITORY="${REGISTRY}/local"
"${PUSH_IMAGE}" --repository "${REPOSITORY}"
"${CRANE}" digest "$REPOSITORY:latest"

# should push image_index with default tags
REPOSITORY="${REGISTRY}/local-index"
"${PUSH_IMAGE_INDEX}" --repository "${REPOSITORY}"
"${CRANE}" digest "$REPOSITORY:nightly"


# should push image without default tags
REPOSITORY="${REGISTRY}/local-wo-tags"
"${PUSH_IMAGE_WO_TAGS}" --repository "${REPOSITORY}"
TAGS=$("${CRANE}" ls "$REPOSITORY")
if [ -n "${TAGS}" ]; then
    echo "image is not supposed to have any tags but got"
    echo "${TAGS}"
    exit 1
fi


# should push image to the repository defined in the file
set -ex
REPOSITORY="${REGISTRY}/repository-file"
"${PUSH_IMAGE_REPOSITORY_FILE}" --repository "${REPOSITORY}"
"${CRANE}" digest "$REPOSITORY:latest"


# should push image with the --tag flag.
REPOSITORY="${REGISTRY}/local-flag-tag"
"${PUSH_IMAGE_WO_TAGS}" --repository "${REPOSITORY}" --tag "custom"
TAGS=$("${CRANE}" ls "$REPOSITORY")
if [ "${TAGS}" != "custom" ]; then
    echo "image is supposed to have custom tag but got"
    echo "${TAGS}"
    exit 1
fi
