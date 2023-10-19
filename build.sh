echo Build started on `date`
export IMAGE_TAG=`git ls-remote --heads origin | grep $(git rev-parse HEAD) | cut -d / -f 3`
if [ "$IMAGE_TAG" = "master" ] ; then export IMAGE_TAG=latest ; fi
export REPO_PATH=`git rev-parse --show-toplevel`
export REPO_NAME=`basename $REPO_PATH`
export IMAGE_REPO_NAME="hive/$REPO_NAME"
export SOURCE_COMMIT=`git rev-parse HEAD`
echo Building branch $IMAGE_TAG from $IMAGE_REPO_NAME
docker build . -t $IMAGE_REPO_NAME:$IMAGE_TAG --build-arg SOURCE_COMMIT="${SOURCE_COMMIT}" --build-arg DOCKER_TAG="${IMAGE_TAG}"

