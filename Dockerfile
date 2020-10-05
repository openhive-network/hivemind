FROM python:3.6 as hivemind-base
LABEL maintainer="Wieslaw Kedzierski wkedzierski@syncad.com"

COPY . /src/hivemind
WORKDIR /src/hivemind
RUN python3 setup.py build && \
    python3 setup.py install --prefix /src/hivemind/install

FROM python:3.6-slim as hivemind
ENV PATH=/src/hivemind/bin:$PATH
ENV PYTHONPATH=/src/hivemind/lib/python3.6/site-packages
COPY --from=hivemind-base /src/hivemind/install /src/hivemind