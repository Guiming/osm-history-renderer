# syntax=docker/dockerfile:1.7

FROM mambaorg/micromamba:2.3.3 AS builder

ARG MAMBA_DOCKERFILE_ACTIVATE=1
COPY --chown=$MAMBA_USER:$MAMBA_USER environment-importer.yml /tmp/environment.yml
RUN micromamba install --yes --name base --file /tmp/environment.yml \
    && micromamba clean --all --yes

WORKDIR /src/importer
COPY --chown=$MAMBA_USER:$MAMBA_USER importer/ /src/importer/
RUN make clean all test \
    && make DESTDIR=/tmp/stage install

FROM mambaorg/micromamba:2.3.3 AS runtime

ARG MAMBA_DOCKERFILE_ACTIVATE=1
COPY --chown=$MAMBA_USER:$MAMBA_USER environment-importer-runtime.yml /tmp/environment.yml
RUN micromamba install --yes --name base --file /tmp/environment.yml \
    && micromamba clean --all --yes

COPY --from=builder /tmp/stage/ /
COPY --chown=$MAMBA_USER:$MAMBA_USER docker/importer-entrypoint.sh /usr/local/bin/osm-history-import

USER root
RUN chmod 0755 /usr/local/bin/osm-history-import
USER $MAMBA_USER

ENV PATH=/opt/conda/bin:$PATH
WORKDIR /history
ENTRYPOINT ["/usr/local/bin/osm-history-import"]
