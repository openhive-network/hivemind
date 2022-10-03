#! /bin/bash

set -euo pipefail

TAG=$(git tag --list 'v1.*' --contains)

if [ -z "$TAG" ]
then
  git tag -f v2.0.0dev1
fi

