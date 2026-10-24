# The image AIDEV runs this project's checks in. .aidev/project.yaml's
# `environment.base` follows common-ci-configuration's python-test-tools:develop and
# AIDEV builds this file on the image that tag names now (BASE_IMAGE), rebuilding when
# the tag moves. Checks run with the caller's uid and, for the slots that start the HAF
# test stack, on that stack's network.
#
# The base brings Python 3.14, psql, postgrest and every test and lint tool (pytest,
# pytest-xdist, tavern, deepdiff, jsondiff, ruff, mypy, ...) at the versions of
# common-ci-configuration's docker-bake.hcl, the ones CI runs. This file adds only what
# it lacks, and pins no tool:
#
#   + create_haf_app_role.sh / common.sh from common-ci-configuration's develop, where
#     scripts/setup_postgres.sh looks for them first (otherwise it curls them)
#   + setup.cfg's install_requires, so `hive` runs from the checkout (PYTHONPATH) with
#     no network at check time
#
# The build context is the repository root; setup.cfg is the only file it copies.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG COMMON_CI=https://gitlab.syncad.com/hive/common-ci-configuration/-/raw/develop/haf-app-tools/scripts
ADD --chmod=755 ${COMMON_CI}/create_haf_app_role.sh /home/hivemind/haf/scripts/create_haf_app_role.sh
ADD --chmod=644 ${COMMON_CI}/common.sh /home/hivemind/haf/scripts/common.sh

# cffi 1.17.1 has no cp314 wheel: build it (gcc, libffi-dev, the Python headers), then
# drop the compilers. The packages go into the base's tools venv, first on PATH.
COPY setup.cfg /tmp/setup.cfg
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gcc libc6-dev libffi-dev python3-dev \
    && python3 -c "import configparser; c = configparser.ConfigParser(); c.read('/tmp/setup.cfg'); \
print('\n'.join(r for r in c['options']['install_requires'].split('\n') if r.strip()))" > /tmp/requirements.txt \
    && python3 -m pip install --no-cache-dir -r /tmp/requirements.txt \
    && apt-get purge -y --auto-remove gcc libc6-dev python3-dev \
    && rm -rf /var/lib/apt/lists/* /tmp/setup.cfg /tmp/requirements.txt

ENV HOME=/tmp PYTHONDONTWRITEBYTECODE=1
ENTRYPOINT []
CMD ["bash"]
