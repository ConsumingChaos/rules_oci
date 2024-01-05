#!/usr/bin/env bash
set -o pipefail -o errexit -o nounset

# Ensure environment is provided by caller
: ${COREUTILS?}
: ${YQ?}
: ${CRANE?}

readonly IMAGE_DIR="{{image_dir}}"
readonly TAGS_FILE="{{tags}}"
readonly FIXED_ARGS=({{fixed_args}})
readonly REPOSITORY_FILE="{{repository_file}}"

REPOSITORY=""
if [ -f $REPOSITORY_FILE ] ; then
  REPOSITORY=$("${COREUTILS}" tr -d '\n' < "$REPOSITORY_FILE")
fi

# set $@ to be FIXED_ARGS+$@
ALL_ARGS=(${FIXED_ARGS[@]+"${FIXED_ARGS[@]}"} $@)
if [[ ${#ALL_ARGS[@]} -gt 0 ]]; then
  set -- ${ALL_ARGS[@]}
fi

TAGS=()
ARGS=()

while (( $# > 0 )); do
  case $1 in
    (-t|--tag)
      TAGS+=( "$2" )
      shift
      shift;;
    (--tag=*)
      TAGS+=( "${1#--tag=}" )
      shift;;
    (-r|--repository)
      REPOSITORY="$2"
      shift
      shift;;
    (--repository=*)
      REPOSITORY="${1#--repository=}"
      shift;;
    (*)
      ARGS+=( "$1" )
      shift;;
  esac
done

DIGEST=$("${YQ}" --unwrapScalar eval '.manifests[0].digest' "${IMAGE_DIR}/index.json")

REFS=$("${COREUTILS}" mktemp)
"${CRANE}" push "${IMAGE_DIR}" "${REPOSITORY}@${DIGEST}" "${ARGS[@]+"${ARGS[@]}"}" --image-refs "${REFS}"

for tag in "${TAGS[@]+"${TAGS[@]}"}"
do
  "${CRANE}" tag $("${COREUTILS}" cat "${REFS}") "${tag}"
done

if [[ -e "${TAGS_FILE:-}" ]]; then
  for tag in $("${COREUTILS}" cat "${TAGS_FILE}")
  do
    "${CRANE}" tag $("${COREUTILS}" cat "${REFS}") "${tag}"
  done
fi
