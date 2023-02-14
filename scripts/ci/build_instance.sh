#! /bin/bash

SCRIPTSDIR="$(dirname "$(realpath "$0")")/.."

export LOG_FILE=build_instance.log
# shellcheck source=../haf/scripts/common.sh
source "$SCRIPTSDIR/../haf/scripts/common.sh"

BUILD_IMAGE_TAG=""
REGISTRY=""
SRCROOTDIR=""


print_help () {
    echo "Usage: $0 <image_tag> <src_dir> <registry_url> [OPTION[=VALUE]]..."
    echo
    echo "Allows to build docker image containing Hivemind installation"
    echo "OPTIONS:"
    echo "  --help  Display this help screen and exit"
    echo
}

while [ $# -gt 0 ]; do
  case "$1" in
    *)
        if [ -z "$BUILD_IMAGE_TAG" ];
        then
          BUILD_IMAGE_TAG=:"${1}"
        elif [ -z "$SRCROOTDIR" ];
        then
          SRCROOTDIR="${1}"
        elif [ -z "$REGISTRY" ];
        then
          REGISTRY=${1}
        else
          echo "ERROR: '$1' is not a valid option/positional argument"
          echo
          print_help
          exit 1
        fi
        ;;
    esac
    shift
done

[[ -z "$BUILD_IMAGE_TAG" ]] && echo "Variable BUILD_IMAGE_TAG must be set" && exit 1
[[ -z "$SRCROOTDIR" ]] && echo "Variable SRCROOTDIR must be set" && exit 1
[[ -z "$REGISTRY" ]] && echo "Variable REGISTRY must be set" && exit 1

echo "Moving into source root directory: ${SRCROOTDIR}"

pushd "$SRCROOTDIR" || exit 1
pwd

"$SRCROOTDIR/scripts/ci/fix_ci_tag.sh"

BUILD_OPTIONS=("--platform=amd64" "--target=instance" "--progress=plain")

if [[ -n "${CI:-}" ]]
then
  BUILD_OPTIONS+=("--push")
fi;

docker buildx build "${BUILD_OPTIONS[@]}" \
  --build-arg CI_REGISTRY_IMAGE="$REGISTRY" \
  --tag "${REGISTRY}instance${BUILD_IMAGE_TAG}" \
  --file Dockerfile .

popd || exit 1