FROM postgres:13 as hivemind
LABEL maintainer="Wieslaw Kedzierski wkedzierski@syncad.com"

COPY . /src/hivemind
WORKDIR /src/hivemind

RUN apt-get update && \
    apt-get install -y python3 python3-dev python3-setuptools git gcc netcat && \
    apt-get -y autoremove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    python3 setup.py build && \
    python3 setup.py install 

ENTRYPOINT [ "/src/hivemind/run_hivemind.sh" ]