# Ensure environment is provided by caller
: ${REGISTRY_BINARY?}
: ${REGISTRY_STORAGE_DIR?}
: ${COREUTILS?}
: ${SED?}

readonly CRANE="${REGISTRY_BINARY}"

function start_registry() {
    local deadline="${1:-5}"
    local registry_pid="${REGISTRY_STORAGE_DIR}/proc.pid"

    "${COREUTILS}" mkdir -p "${REGISTRY_STORAGE_DIR}"
    "${CRANE}" registry serve --disk="${REGISTRY_STORAGE_DIR}" --address=localhost:0 >> "${REGISTRY_STORAGE_DIR}/registry.log" 2>&1 &
    "${COREUTILS}" echo "$!" > "${registry_pid}"

    local timeout=$((SECONDS+${deadline}))

    while [ "${SECONDS}" -lt "${timeout}" ]; do
        local port=$("${COREUTILS}" cat "${REGISTRY_STORAGE_DIR}/registry.log" | "${SED}" -nr 's/.+serving on port ([0-9]+)/\1/p')
        if [ -n "${port}" ]; then
            break
        fi
    done
    if [ -z "${port}" ]; then
        "${COREUTILS}" echo "registry didn't become ready within ${deadline}s." >&2
        return 1
    fi
    "${COREUTILS}" echo "127.0.0.1:${port}"
    return 0
}

function stop_registry() {
    local registry_pid="${REGISTRY_STORAGE_DIR}/proc.pid"
    if [[ ! -f "${registry_pid}" ]]; then
        return 0
    fi
    "${COREUTILS}" kill -9 "$("${COREUTILS}" cat "${registry_pid}")" || true
    "${COREUTILS}" rm -f "${registry_pid}"
    return 0
}
