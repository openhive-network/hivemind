#! /bin/bash

set -euo pipefail 

REGISTRY=$1

docker build --build-arg CI_REGISTRY_IMAGE=$REGISTRY --build-arg CI_DOCKER_USER=hivemind -t $REGISTRY/ci_base_image:3.8 -f Dockerfile .
