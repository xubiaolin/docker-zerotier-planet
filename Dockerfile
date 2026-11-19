FROM node:22-bookworm-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates git python3 && rm -rf /var/lib/apt/lists/*

FROM rust:1.94-slim-bookworm AS zerotier
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates git libssl-dev pkg-config && rm -rf /var/lib/apt/lists/*
ENV CARGO_BUILD_JOBS=3 CARGO_NET_GIT_FETCH_WITH_CLI=true
ARG TAG=1.16.2
WORKDIR /build/ZeroTierOne
RUN git clone --depth=1 --branch "${TAG}" https://github.com/zerotier/ZeroTierOne.git . \
    && make -j2 ZT_NONFREE=1
COPY patch/mkworld_custom.cpp patch/mkworld.mk ./
RUN make -f Makefile -f mkworld.mk ZT_NONFREE=1 mkworld \
    && strip mkworld zerotier-one

FROM builder AS ztncui
WORKDIR /build
RUN git clone https://github.com/key-networks/ztncui.git \
    && cd ztncui && git checkout --detach 1b2284864de48d2dcae22582fff122fe24909c3d \
    && cd src && npm pkg set dependencies.argon2=0.44.0 \
    && npm install --omit=dev --no-audit --no-fund \
    && node -e "require('argon2')"

FROM node:22-bookworm-slim
LABEL org.zerotier-planet.retry-safe="1"
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates util-linux \
    && rm -rf /var/lib/apt/lists/*
COPY --from=zerotier /build/ZeroTierOne/zerotier-one /usr/sbin/
COPY --from=zerotier /build/ZeroTierOne/mkworld /usr/local/bin/
RUN ln -s zerotier-one /usr/sbin/zerotier-idtool && ln -s zerotier-one /usr/sbin/zerotier-cli
COPY --from=ztncui /build/ztncui/src /opt/ztncui/src
RUN mv /opt/ztncui/src/etc /opt/ztncui/etc.defaults \
    && ln -s /app/ztncui/src/etc /opt/ztncui/src/etc \
    && ln -s /app/ztncui/src/.env /opt/ztncui/src/.env
WORKDIR /app
COPY patch/*.js patch/*.sh ./
VOLUME ["/app/dist","/app/ztncui","/var/lib/zerotier-one","/app/config"]
HEALTHCHECK --interval=10s --timeout=8s --start-period=30s --retries=3 \
    CMD ["/bin/sh", "/app/healthcheck.sh"]
CMD ["flock", "-n", "-F", "/var/lib/zerotier-one", "/bin/bash", "/app/entrypoint.sh"]
