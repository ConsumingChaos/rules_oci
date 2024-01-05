#!/usr/bin/env bash
set -o pipefail -o errexit -o nounset

# Ensure environment is provided by caller
: ${REGISTRY_BINARY?}
: ${REGISTRY_LAUNCHER?}
: ${REGISTRY_STORAGE_DIR?}
: ${EMPTY_TAR?}
: ${CRANE?}
: ${COREUTILS?}
: ${GREP?}
: ${JQ?}
: ${SED?}

# Constants
readonly STDERR="${REGISTRY_STORAGE_DIR}/output.log"
# shellcheck disable=SC2016
readonly ENV_EXPAND_FILTER=\
'[$raw | match("\\${?([a-zA-Z0-9_]+)}?"; "gm")] | reduce .[] as $match (
    {parts: [], prev: 0};
    {parts: (.parts + [$raw[.prev:$match.offset], $envs[$match.captures[0].string]]), prev: ($match.offset + $match.length)}
) | .parts + [$raw[.prev:]] | join("")'

on_exit() {
    local last_cmd_exit_code=$?
    set +o errexit
    stop_registry "${REGISTRY_STORAGE_DIR}"
    local stop_registry_exit_code=$?
    if [[ $last_cmd_exit_code != 0 ]] || [[ $stop_registry_exit_code != 0 ]]; then
        "${COREUTILS}" cat "${STDERR}"
        if "${GREP}" -q "MANIFEST_INVALID" "${REGISTRY_STORAGE_DIR}/registry.log"; then
          "${COREUTILS}" cat << EOF
Explanation:

Zot registry does not support docker manifests.
Crane registry does support both oci and docker images, but is more memory hungry.
If you want to use the crane registry, remove "zot_version" from "oci_register_toolchains".
EOF
        fi
        "${COREUTILS}" echo "Logs from registry:"
        "${COREUTILS}" echo ""
        "${COREUTILS}" cat "${REGISTRY_STORAGE_DIR}/registry.log"
    fi
    "${COREUTILS}" rm -f $STDERR
    "${COREUTILS}" rm -f "${REGISTRY_STORAGE_DIR}/registry.log"
}

# Upon exiting, stop the registry and print STDERR on non-zero exit code.
trap "on_exit" EXIT

# Redirect stderr to the $STDERR temp file for the rest of the script.
exec 2>>"${STDERR}"

# shellcheck disable=SC1090
source "${REGISTRY_LAUNCHER}"
REGISTRY=$(start_registry)


function base_from_scratch() {
    local raw_platform="$1"
    local ref="${REGISTRY}/scratch:latest"
    ref="$("${CRANE}" append --oci-empty-base -t "${ref}" "-f" "${EMPTY_TAR}")"
    ref=$("${CRANE}" config "${ref}" | "${JQ}"  ".rootfs.diff_ids = [] | .history = []" | "${CRANE}" edit config "${ref}")
    ref=$("${CRANE}" manifest "${ref}" | "${JQ}"  ".layers = []" | "${CRANE}" edit manifest "${ref}")

    IFS='/' read -r -a platform <<< "$raw_platform"

    local filter=".os = \"${platform[0]}\" | .architecture = \"${platform[1]}\""

    if [ -n "${platform[2]:-}" ]; then
        filter+=" | .variant = \"${platform[2]}\""
    fi
    "${CRANE}" config "${ref}" | "${JQ}" "${filter}" | "${CRANE}" edit config "${ref}"
}

FIXED_ARGS=()
ENV_EXPANSIONS=()

for ARG in "$@"; do
    case "$ARG" in
        (--scratch=*)
          REF=$(base_from_scratch "${ARG#--scratch=}")
          FIXED_ARGS+=("${REF}")
        ;;
        (--from=*)
          REF=$("${CRANE}" push "${ARG#--from=}" "${REGISTRY}/layout:latest")
          FIXED_ARGS+=("${REF}")
        ;;
        # NB: the '|| [-n $in]' in all flags below  expression is needed to process
        # the final line, in case the input file doesn't have a trailing newline.
        (--env-file=*)
          while IFS= read -r in || [ -n "$in" ]; do
            if [[ "${in}" = *\$* ]]; then
              ENV_EXPANSIONS+=( "${in}" )
            else
              FIXED_ARGS+=( "--env=${in}" )
            fi
          done <"${ARG#--env-file=}"
          ;;
        (--labels-file=*)
          while IFS= read -r in || [ -n "$in" ]; do
            FIXED_ARGS+=("--label=$in")
          done <"${ARG#--labels-file=}"
          ;;
        (--annotations-file=*)
          while IFS= read -r in || [ -n "$in" ]; do
            FIXED_ARGS+=("--annotation=$in")
          done <"${ARG#--annotations-file=}"
          ;;
        (--cmd-file=*)
          while IFS= read -r in || [ -n "$in" ]; do
            FIXED_ARGS+=("--cmd=$in")
          done <"${ARG#--cmd-file=}"
          ;;
        (--entrypoint-file=*)
          while IFS= read -r in || [ -n "$in" ]; do
            FIXED_ARGS+=("--entrypoint=$in")
          done <"${ARG#--entrypoint-file=}"
          ;;
        (--exposed-ports-file=*)
          while IFS= read -r in || [ -n "$in" ]; do
                  FIXED_ARGS+=("--exposed-ports=$in")
                done <"${ARG#--exposed-ports-file=}"
                ;;
              (*) FIXED_ARGS+=( "${ARG}" )
          esac
done

REF=$("${CRANE}" "${FIXED_ARGS[@]}")

# Expand environment variables
if [ ${#ENV_EXPANSIONS[@]} -ne 0 ]; then
    base_env=$( "${CRANE}" config "${REF}" | "${JQ}" -r '.config.Env | map(. | split("=") | {"key": .[0], "value": .[1:] | join("=")}) | from_entries')
    environment_args=()
    for expansion in "${ENV_EXPANSIONS[@]}"
    do
        IFS="=" read -r key value <<< "${expansion}"
        value_from_base=$("${JQ}" -nr --arg raw "${value}" --argjson envs "${base_env}" "${ENV_EXPAND_FILTER}")
        environment_args+=( "--env" "${key}=${value_from_base}" )
    done
    REF=$("${CRANE}" mutate "${REF}" "${environment_args[@]}")
fi

"${CRANE}" pull "${REF}" "./${REGISTRY_STORAGE_DIR}" --format=oci --annotate-ref
"${COREUTILS}" mv "${REGISTRY_STORAGE_DIR}/index.json" "${REGISTRY_STORAGE_DIR}/temp.json"
# shellcheck disable=SC2016
"${JQ}" --arg ref "${REF}" '.manifests |= map(select(.annotations["org.opencontainers.image.ref.name"] == $ref)) | del(.manifests[0].annotations)' "${REGISTRY_STORAGE_DIR}/temp.json" >  "${REGISTRY_STORAGE_DIR}/index.json"
"${COREUTILS}" rm "${REGISTRY_STORAGE_DIR}/temp.json"
"${CRANE}" layout gc "./${REGISTRY_STORAGE_DIR}"
