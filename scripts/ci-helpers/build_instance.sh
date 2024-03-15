#! /bin/bash

set -e

SCRIPTSDIR="$(dirname "$(realpath "$0")")/.."

export LOG_FILE=build_instance.log
# shellcheck source=../haf/scripts/common.sh
source "$SCRIPTSDIR/../haf/scripts/common.sh"

BUILD_IMAGE_TAG=""
REGISTRY=""
SRCROOTDIR=""

print_help () {
cat <<EOF
Usage: $0 <image_tag> <src_dir> <registry_url> [OPTION[=VALUE]]...
Allows to build docker image containing Hivemind installation
The image will be tagged with name '<registry_url>/instance:instance-<image_tag>'

OPTIONS:
  -?,--help                        Display this help screen and exit
  --dot-env-filename=<filename> File name of the dot env file to be generated
  --dot-env-var-name=<var name> Vaiable name to be used in the generated file (default: 'IMAGE')
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -?|--help)
        print_help
        exit 0
        ;;
    --dot-env-filename=*)
        DOT_ENV_FILENAME="${1#*=}"
        ;;
    --dot-env-var-name=*)
        DOTENV_VAR_NAME="${1#*=}"
        ;;
    *)
        if [ -z "$BUILD_IMAGE_TAG" ];
        then
          BUILD_IMAGE_TAG="${1}"
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

[[ -z "$BUILD_IMAGE_TAG" ]] && printf "Missing argument #1 - image tag suffix\n\n" && print_help && exit 1
[[ -z "$SRCROOTDIR" ]] && printf "Missing argument #2 - source directory path\n\n" && print_help && exit 1
[[ -z "$REGISTRY" ]] && printf "Missing argument #3 - target container registry URL\n\n" && print_help && exit 1

# Supplement a registry path by trailing slash (if needed)
[[ "${REGISTRY}" != */ ]] && REGISTRY="${REGISTRY}/"

printf "Moving into source root directory: %s\n" "$SRCROOTDIR"

pushd "$SRCROOTDIR"
pwd

"$SRCROOTDIR/scripts/ci/fix_ci_tag.sh"

CI_IMAGE_TAG=${CI_IMAGE_TAG:-"python-3.8-slim-1"} # see scripts/ci/build_ci_base_image.sh for the current tag
BUILD_OPTIONS=("--platform=linux/amd64" "--target=instance" "--progress=plain")
TAG="${REGISTRY}instance:$BUILD_IMAGE_TAG"
MINIMAL_TAG="${REGISTRY}minimal-instance:$BUILD_IMAGE_TAG"

# On CI push the images to the registry
if [[ -n "${CI:-}" ]]; then
  BUILD_OPTIONS+=("--push")
else
  BUILD_OPTIONS+=("--load")
fi

BUILD_TIME="$(date -uIseconds)"

GIT_COMMIT_SHA="$(git rev-parse HEAD || true)"
if [ -z "$GIT_COMMIT_SHA" ]; then
  GIT_COMMIT_SHA="[unknown]"
fi

GIT_CURRENT_BRANCH="$(git branch --show-current || true)"
if [ -z "$GIT_CURRENT_BRANCH" ]; then
  GIT_CURRENT_BRANCH="$(git describe --abbrev=0 --all | sed 's/^.*\///' || true)"
  if [ -z "$GIT_CURRENT_BRANCH" ]; then
    GIT_CURRENT_BRANCH="[unknown]"
  fi
fi

GIT_LAST_LOG_MESSAGE="$(git log -1 --pretty=%B || true)"
if [ -z "$GIT_LAST_LOG_MESSAGE" ]; then
  GIT_LAST_LOG_MESSAGE="[unknown]"
fi

GIT_LAST_COMMITTER="$(git log -1 --pretty="%an <%ae>" || true)"
if [ -z "$GIT_LAST_COMMITTER" ]; then
  GIT_LAST_COMMITTER="[unknown]"
fi

GIT_LAST_COMMIT_DATE="$(git log -1 --pretty="%aI" || true)"
if [ -z "$GIT_LAST_COMMIT_DATE" ]; then
  GIT_LAST_COMMIT_DATE="[unknown]"
fi

docker buildx build "${BUILD_OPTIONS[@]}" \
  --build-context "runtime=docker-image://${REGISTRY}runtime:${CI_IMAGE_TAG}" \
  --build-arg BUILD_TIME="$BUILD_TIME" \
  --build-arg GIT_COMMIT_SHA="$GIT_COMMIT_SHA" \
  --build-arg GIT_CURRENT_BRANCH="$GIT_CURRENT_BRANCH" \
  --build-arg GIT_LAST_LOG_MESSAGE="$GIT_LAST_LOG_MESSAGE" \
  --build-arg GIT_LAST_COMMITTER="$GIT_LAST_COMMITTER" \
  --build-arg GIT_LAST_COMMIT_DATE="$GIT_LAST_COMMIT_DATE" \
  --tag "$TAG" \
  --file Dockerfile .

# Since CI pushes the image directly to the registry, it needs to be pulled to be tagged
if [[ -n "${CI:-}" ]]; then
 docker pull "$TAG"
fi

docker tag "$TAG" "$MINIMAL_TAG"

[[ -n "${DOT_ENV_FILENAME:-}" ]] && echo "${DOTENV_VAR_NAME:-IMAGE}=$TAG" > "$DOT_ENV_FILENAME"

popd