#! /bin/bash

[[ -z "$DOCKER_HUB_USER" ]] && echo "Variable DOCKER_HUB_USER must be set" && exit 1
[[ -z "$DOCKER_HUB_PASSWORD" ]] && echo "Variable DOCKER_HUB_PASSWORD must be set" && exit 1

set -e

docker login -u "$CI_REGISTRY_USER" -p "$CI_REGISTRY_PASSWORD" "$CI_REGISTRY"
docker login -u "$DOCKER_HUB_USER" -p "$DOCKER_HUB_PASSWORD"

INSTANCE_TAG="${CI_REGISTRY_IMAGE}/instance:instance-${CI_COMMIT_SHA}"
docker pull "$INSTANCE_TAG"

# Turn PEP 440-compliant version number into a Docker-compliant tag
#shellcheck disable=SC2001
TAG=$(echo "$CI_COMMIT_TAG" | sed 's/[!+]/-/g')
docker tag "$INSTANCE_TAG" "${CI_REGISTRY_IMAGE}/instance:instance-${TAG}"
docker tag "$INSTANCE_TAG" "hiveio/hivemind:${TAG}"

docker images

docker push "${CI_REGISTRY_IMAGE}/instance:instance-${TAG}"
docker push "hiveio/hivemind:${TAG}"