# syntax=docker/dockerfile:1.7

# This digest pins the ubuntu:22.04 OCI index; the release target selects its
# Linux AMD64 manifest and verifies the architecture inside both stages.
ARG UBUNTU_IMAGE=ubuntu:22.04@sha256:0e0a0fc6d18feda9db1590da249ac93e8d5abfea8f4c3c0c849ce512b5ef8982

FROM --platform=$TARGETPLATFORM ${UBUNTU_IMAGE} AS builder

ARG SOURCE_REVISION
ARG SOURCE_DATE_EPOCH

RUN set -eux; \
    test "$(dpkg --print-architecture)" = amd64; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        autoconf \
        build-essential \
        ca-certificates \
        git \
        libbz2-dev \
        libcurl4-openssl-dev \
        libgflags-dev \
        liblz4-dev \
        libsnappy-dev \
        libssl-dev \
        libuuid1 \
        libzstd-dev \
        nasm \
        pkg-config \
        uuid-dev \
        zlib1g-dev; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/keydb
COPY . .

RUN set -eux; \
    printf '%s\n' "$SOURCE_REVISION" | grep -Eq '^[0-9a-f]{40}$'; \
    printf '%s\n' "$SOURCE_DATE_EPOCH" | grep -Eq '^[0-9]+$'; \
    make distclean; \
    KEYDB_BUILD_GIT_SHA1="$SOURCE_REVISION" \
    KEYDB_BUILD_GIT_DIRTY=0 \
    SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
        make -j1 \
            BUILD_TLS=yes \
            ENABLE_FLASH=no \
            NO_MOTD=yes \
            OPTIMIZATION="-O2 -flto=1"; \
    strip \
        src/keydb-benchmark \
        src/keydb-check-aof \
        src/keydb-check-rdb \
        src/keydb-cli \
        src/keydb-diagnostic-tool \
        src/keydb-sentinel \
        src/keydb-server

RUN src/keydb-server --version | grep -F "sha=$(printf '%s' "$SOURCE_REVISION" | cut -c1-8):0"

FROM --platform=$TARGETPLATFORM ${UBUNTU_IMAGE} AS runtime

ARG IMAGE_VERSION
ARG SOURCE_REVISION

LABEL org.opencontainers.image.title="SEObserver KeyDB" \
      org.opencontainers.image.description="SEObserver downstream KeyDB distribution" \
      org.opencontainers.image.source="https://github.com/SEObserver/KeyDB" \
      org.opencontainers.image.url="https://github.com/SEObserver/KeyDB" \
      org.opencontainers.image.documentation="https://github.com/SEObserver/KeyDB/blob/seobserver/6.3/SEOBSERVER.md" \
      org.opencontainers.image.licenses="BSD-3-Clause" \
      org.opencontainers.image.version="$IMAGE_VERSION" \
      org.opencontainers.image.revision="$SOURCE_REVISION"

RUN set -eux; \
    test "$(dpkg --print-architecture)" = amd64; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        gosu \
        libbz2-1.0 \
        liblz4-1 \
        libsnappy1v5 \
        libssl3 \
        libuuid1 \
        libzstd1 \
        zlib1g; \
    rm -rf /var/lib/apt/lists/*; \
    groupadd --gid 999 keydb; \
    useradd --uid 999 --gid 999 --home-dir /data --no-create-home --shell /usr/sbin/nologin keydb; \
    install -d -o keydb -g keydb /data /flash /etc/keydb /usr/share/licenses/keydb

COPY --from=builder /usr/src/keydb/src/keydb-server /usr/src/keydb/src/keydb-sentinel /usr/src/keydb/src/keydb-cli /usr/src/keydb/src/keydb-benchmark /usr/src/keydb/src/keydb-check-rdb /usr/src/keydb/src/keydb-check-aof /usr/src/keydb/src/keydb-diagnostic-tool /usr/local/bin/
COPY --from=builder /usr/src/keydb/keydb.conf /etc/keydb/keydb.conf
COPY --from=builder /usr/src/keydb/COPYING /usr/share/licenses/keydb/COPYING
COPY pkg/docker/seobserver/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN set -eux; \
    sed -ri 's/^(bind .*)/# \1/' /etc/keydb/keydb.conf; \
    sed -ri 's/^(dir ).*/\1\/data/' /etc/keydb/keydb.conf; \
    sed -ri 's/^(logfile ).*/\1""/' /etc/keydb/keydb.conf; \
    sed -ri 's/^(protected-mode )yes/\1no/' /etc/keydb/keydb.conf; \
    ln -s keydb-server /usr/local/bin/redis-server; \
    ln -s keydb-sentinel /usr/local/bin/redis-sentinel; \
    ln -s keydb-cli /usr/local/bin/redis-cli; \
    ln -s keydb.conf /etc/keydb/redis.conf; \
    chmod 0755 /usr/local/bin/docker-entrypoint.sh

VOLUME ["/data"]
WORKDIR /data
ENV KEYDB_PRO_DIRECTORY=/usr/local/bin/
USER 999:999
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
EXPOSE 6379
STOPSIGNAL SIGTERM
CMD ["keydb-server", "/etc/keydb/keydb.conf"]
