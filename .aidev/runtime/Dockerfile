# The image AIDEV runs this project's checks in (`environment.image` in
# .aidev/project.yaml). Checks run with the caller's uid and, for the slots that
# start the HAF test stack, on that stack's network. It mirrors the `runtime`
# stage of ./Dockerfile:
#
#   python:3.14-slim-bookworm + postgresql-client, git
#   + the postgrest binary of common-ci-configuration/postgrest (POSTGREST_VERSION there)
#   + create_haf_app_role.sh / common.sh from common-ci-configuration, where
#     scripts/setup_postgres.sh looks for them first (otherwise it curls them)
#   + setup.cfg's install_requires, pytest, ruff and mypy (pinned: the `ruff` step's and
#     the quality typecheck's verdicts must not move with a new release), so `hive` runs from the checkout
#     (PYTHONPATH) with no network at check time.
#
# Its inputs are this file and setup.cfg (the only file in the build context).
# Build and pin it with .aidev/runtime/build.sh; see .aidev/README.md.
FROM registry.gitlab.syncad.com/hive/common-ci-configuration/postgrest@sha256:ad2d14b8699accf5d1fccf8314b25d835e6aaddadaec35597a5dac1f002eb457 AS postgrest

FROM python:3.14-slim-bookworm@sha256:48b13b003dda20b16f9442b8475aa05fe21bf6579a8c881db92ffb4d8fd20f83

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends postgresql-client git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=postgrest /bin/postgrest /usr/local/bin/postgrest

ARG COMMON_CI=https://gitlab.syncad.com/hive/common-ci-configuration/-/raw/7dffa23eb3612b0e2f049e98260028c0134c0156/haf-app-tools/scripts
ADD --chmod=755 --checksum=sha256:dcdda23ab14b83a45c475708485c09d93575b9a950df86f2cb211a4162385836 \
    ${COMMON_CI}/create_haf_app_role.sh /home/hivemind/haf/scripts/create_haf_app_role.sh
ADD --chmod=644 --checksum=sha256:3c696b7be441c1e738cf630d3c015301e0ecd8dcd78a865fbf81fae244f9562c \
    ${COMMON_CI}/common.sh /home/hivemind/haf/scripts/common.sh

# cffi 1.17.1 has no cp314 wheel: build it the way ./Dockerfile's ci-base-image does
# (gcc, libffi-dev), then drop the compilers.
COPY setup.cfg /tmp/setup.cfg
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gcc libffi-dev libc6-dev \
    && python3 -c "import configparser; c = configparser.ConfigParser(); c.read('/tmp/setup.cfg'); \
print('\n'.join(r for r in c['options']['install_requires'].split('\n') if r.strip()))" > /tmp/requirements.txt \
    && pip install --no-cache-dir -r /tmp/requirements.txt pytest==8.4.2 ruff==0.16.10 mypy==2.4.0 \
    && apt-get purge -y --auto-remove gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/* /tmp/setup.cfg /tmp/requirements.txt

ENV HOME=/tmp PYTHONDONTWRITEBYTECODE=1
ENTRYPOINT []
CMD ["bash"]
