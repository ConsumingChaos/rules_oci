# Ensure environment is provided by caller
: ${REGISTRY_BINARY?}
: ${REGISTRY_STORAGE_DIR?}
: ${COREUTILS?}
: ${SED?}

readonly ZOT="${REGISTRY_BINARY}"
readonly TMPDIR=$("${COREUTILS}" mktemp)

function start_registry() {
    local deadline="${1:-5}"
    local config_path="${REGISTRY_STORAGE_DIR}/config.json"
    local registry_pid="${REGISTRY_STORAGE_DIR}/proc.pid"

    "${COREUTILS}" cat > "${config_path}" <<EOF
{
    "storage": { "rootDirectory": "${REGISTRY_STORAGE_DIR}/..", "dedupe": false, "commit": true },
    "http":{ "port": "0", "address": "127.0.0.1" },
    "log":{ "level": "info" }
}
EOF
    HOME="${TMPDIR}" "${ZOT}" serve "${config_path}" >> "${REGISTRY_STORAGE_DIR}/registry.log" 2>&1 &
    "${COREUTILS}" echo "$!" > "${registry_pid}"

    local timeout=$((SECONDS+${deadline}))

    while [ "${SECONDS}" -lt "${timeout}" ]; do
        local port=$("${COREUTILS}" cat "${REGISTRY_STORAGE_DIR}/registry.log" | "${SED}" -nr 's/.+"port":([0-9]+),.+/\1/p')
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
    "${COREUTILS}" rm -rf "${REGISTRY_STORAGE_DIR}/.uploads"
    "${COREUTILS}" rm -r "${REGISTRY_STORAGE_DIR}/config.json"
    local registry_pid="${REGISTRY_STORAGE_DIR}/proc.pid"
    if [[ ! -f "${registry_pid}" ]]; then
        return 0
    fi
    "${COREUTILS}" kill -9 "$(cat "${registry_pid}")" || true
    "${COREUTILS}" rm -f "${registry_pid}"
    return 0
}
