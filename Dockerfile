FROM python:3.6 as hivemind-base
LABEL maintainer="Wieslaw Kedzierski wkedzierski@syncad.com"

COPY . /src/hivemind
WORKDIR /src/hivemind
RUN python3 setup.py build && \
    python3 setup.py install --prefix /src/hivemind/install

FROM python:3.6-slim as hivemind

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client iputils-ping\
    && rm -rf /var/lib/apt/lists/*

ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONFAULTHANDLER 1
ENV PATH=/src/hivemind/bin:$PATH
ENV PYTHONPATH=/src/hivemind/lib/python3.6/site-packages

ARG user
ENV user=${user}
USER ${user}

WORKDIR /src/hivemind

COPY --from=hivemind-base /src/hivemind/install /src/hivemind
COPY ./scripts/run_hivemind.sh /src/hivemind/run_hivemind.sh
ENTRYPOINT [ "/src/hivemind/run_hivemind.sh" ]