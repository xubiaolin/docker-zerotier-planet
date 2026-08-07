# syntax=docker/dockerfile:1.7

ARG NODE_IMAGE=node:20-bookworm-slim@sha256:2cf067cfed83d5ea958367df9f966191a942351a2df77d6f0193e162b5febfc0

FROM ${NODE_IMAGE} AS build-toolchain

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        libssl-dev \
        pkg-config \
        python3 \
    && rm -rf /var/lib/apt/lists/*

FROM build-toolchain AS zerotier-builder

ARG ZEROTIER_VERSION=1.16.2
ARG ZEROTIER_COMMIT=""

WORKDIR /build
RUN git clone --filter=blob:none --no-checkout https://github.com/zerotier/ZeroTierOne.git \
    && cd ZeroTierOne \
    && git fetch --depth=1 origin "refs/tags/${ZEROTIER_VERSION}:refs/tags/${ZEROTIER_VERSION}" \
    && git checkout --detach "refs/tags/${ZEROTIER_VERSION}" \
    && if [ -n "${ZEROTIER_COMMIT}" ]; then test "$(git rev-parse HEAD)" = "${ZEROTIER_COMMIT}"; fi \
    && make -j"$(nproc)" ZT_NONFREE=1 ZT_SSO_SUPPORTED=0 \
    && ./zerotier-one -v

FROM build-toolchain AS ztncui-builder

ARG ZTNCUI_COMMIT=1b2284864de48d2dcae22582fff122fe24909c3d

WORKDIR /build
RUN git clone --filter=blob:none https://github.com/key-networks/ztncui.git \
    && cd ztncui \
    && git checkout --detach "${ZTNCUI_COMMIT}" \
    && test "$(git rev-parse HEAD)" = "${ZTNCUI_COMMIT}"

COPY container/ztncui-package-lock.json /build/ztncui/src/package-lock.json
RUN cd /build/ztncui/src \
    && npm ci --omit=dev \
    && npm audit --omit=dev --audit-level=critical \
    && npm cache clean --force

FROM ${NODE_IMAGE} AS runtime

ENV DEBIAN_FRONTEND=noninteractive

ARG ZEROTIER_VERSION=1.16.2
ARG ZEROTIER_COMMIT=""
ARG ZTNCUI_COMMIT=1b2284864de48d2dcae22582fff122fe24909c3d
ARG PROJECT_REVISION=unknown

LABEL org.opencontainers.image.title="Docker ZeroTier Planet" \
      org.opencontainers.image.description="Self-hosted ZeroTier Planet and network controller" \
      org.opencontainers.image.source="https://github.com/xubiaolin/docker-zerotier-planet" \
      org.opencontainers.image.version="${ZEROTIER_VERSION}" \
      org.opencontainers.image.revision="${PROJECT_REVISION}" \
      io.zerotier.planet.zerotier.version="${ZEROTIER_VERSION}" \
      io.zerotier.planet.zerotier.commit="${ZEROTIER_COMMIT}" \
      io.zerotier.planet.ztncui.commit="${ZTNCUI_COMMIT}"

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        openssl \
        supervisor \
        tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 2222 planet \
    && useradd --uid 2222 --gid planet --home-dir /nonexistent --shell /usr/sbin/nologin planet

COPY --from=zerotier-builder /build/ZeroTierOne/zerotier-one /usr/sbin/zerotier-one
RUN ln -s zerotier-one /usr/sbin/zerotier-cli \
    && ln -s zerotier-one /usr/sbin/zerotier-idtool

COPY --from=ztncui-builder /build/ztncui/src /opt/ztncui/src
RUN mv /opt/ztncui/src/etc /opt/ztncui/etc.defaults \
    && ln -s /app/ztncui/state/etc /opt/ztncui/src/etc

COPY container /opt/planet/container
RUN find /opt/planet/container -type d -exec chmod 0755 {} + \
    && find /opt/planet/container -type f -exec chmod 0644 {} + \
    && chmod 0755 \
        /opt/planet/container/entrypoint.sh \
        /opt/planet/container/healthcheck.sh \
        /opt/planet/container/supervisor-exit-on-fatal.sh \
    && mkdir -p /app/config /app/dist /app/ztncui/state /var/lib/zerotier-one \
    && chown -R planet:planet /app/config /app/dist /app/ztncui

ENV ZEROTIER_VERSION=${ZEROTIER_VERSION} \
    ZTNCUI_COMMIT=${ZTNCUI_COMMIT} \
    CONFIG_PATH=/app/config \
    DIST_PATH=/app/dist \
    ZTNCUI_STATE_PATH=/app/ztncui/state \
    ZEROTIER_PATH=/var/lib/zerotier-one

EXPOSE 9994/tcp 9994/udp 3443/tcp 3000/tcp

VOLUME ["/app/config", "/app/dist", "/app/ztncui", "/var/lib/zerotier-one"]

HEALTHCHECK --interval=15s --timeout=5s --start-period=45s --retries=4 \
    CMD ["/opt/planet/container/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/planet/container/entrypoint.sh"]
