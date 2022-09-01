#! /bin/bash

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
SCRIPTSDIR="$SCRIPTPATH/.."

LOG_FILE=build_instance.log
source "$SCRIPTSDIR/../haf/scripts/common.sh"

BUILD_IMAGE_TAG=""
REGISTRY=""
SRCROOTDIR=""

IMAGE_TAG_PREFIX=""


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

TST_IMGTAG=${BUILD_IMAGE_TAG:?"Missing arg #1 to specify built image tag"}
TST_SRCDIR=${SRCROOTDIR:?"Missing arg #2 to specify source directory"}
TST_REGISTRY=${REGISTRY:?"Missing arg #3 to specify target container registry"}

echo "Moving into source root directory: ${SRCROOTDIR}"

pushd "$SRCROOTDIR"
pwd

"$SRCROOTDIR/scripts/ci/fix_ci_tag.sh"

docker build --target=instance \
  --build-arg CI_REGISTRY_IMAGE=$REGISTRY \
  --build-arg BUILD_IMAGE_TAG=$BUILD_IMAGE_TAG -t ${REGISTRY}${IMAGE_TAG_PREFIX}instance${BUILD_IMAGE_TAG} -f Dockerfile .

popd


