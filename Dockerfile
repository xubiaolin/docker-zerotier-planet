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
    && make -j2 ZT_NONFREE=1 \
    && git rev-parse HEAD > upstream-revision
COPY patch/mkworld_custom.cpp patch/mkworld.mk ./
RUN make -f Makefile -f mkworld.mk ZT_NONFREE=0 mkworld \
    && nm -C mkworld > mkworld.symbols \
    && if grep -qE 'EmbeddedNetworkController|ZeroTier::OneService' mkworld.symbols; then \
        echo 'mkworld unexpectedly links daemon or controller code' >&2; exit 1; \
    fi \
    && strip mkworld zerotier-one

FROM builder AS ztncui
WORKDIR /build
RUN git clone https://github.com/key-networks/ztncui.git \
    && cd ztncui && git checkout --detach 1b2284864de48d2dcae22582fff122fe24909c3d
WORKDIR /build/ztncui
COPY patch/ztncui/package-lock.json src/
COPY patch/ztncui/login.patch /tmp/ztncui-login.patch
RUN git apply /tmp/ztncui-login.patch \
    && cd src && npm pkg set dependencies.argon2=0.44.0 dependencies.ip-address=10.7.6 \
    && npm ci --omit=dev --no-audit --no-fund \
    && node -e "require('argon2')"

FROM node:22-bookworm-slim
LABEL org.zerotier-planet.retry-safe="1"
LABEL org.zerotier-planet.secure-admin="1"
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates util-linux \
    && rm -rf /var/lib/apt/lists/*
COPY --from=zerotier /build/ZeroTierOne/zerotier-one /usr/sbin/
COPY --from=zerotier /build/ZeroTierOne/mkworld /usr/local/bin/
COPY --from=zerotier /build/ZeroTierOne/LICENSE.txt /build/ZeroTierOne/LICENSE-MPL.txt /usr/share/doc/zerotier/
COPY --from=zerotier /build/ZeroTierOne/nonfree/LICENSE.md /usr/share/doc/zerotier/nonfree/LICENSE.md
COPY --from=zerotier /build/ZeroTierOne/upstream-revision /usr/share/doc/zerotier/upstream-revision
COPY patch/mkworld_custom.cpp patch/mkworld.mk Dockerfile /usr/share/doc/zerotier/build/
ARG PROJECT_REVISION
RUN cp /usr/share/common-licenses/GPL-3 /usr/share/doc/zerotier/build/COPYING \
    && printf 'ZeroTier One source for zerotier-one and the core used by mkworld\nhttps://github.com/zerotier/ZeroTierOne/tree/%s\n\nLocal mkworld source and build files are in the build directory alongside this notice.\n' \
        "$(cat /usr/share/doc/zerotier/upstream-revision)" > /usr/share/doc/zerotier/SOURCE.txt \
    && if [ -n "$PROJECT_REVISION" ]; then \
        printf '\nDocker ZeroTier Planet source and build files\nhttps://github.com/xubiaolin/docker-zerotier-planet/tree/%s\n' \
            "$PROJECT_REVISION" >> /usr/share/doc/zerotier/SOURCE.txt; \
    fi
RUN ln -s zerotier-one /usr/sbin/zerotier-idtool && ln -s zerotier-one /usr/sbin/zerotier-cli
COPY --from=ztncui /build/ztncui/src /opt/ztncui/src
COPY --from=ztncui /build/ztncui/LICENSE /usr/share/doc/ztncui/LICENSE
RUN rm -r /opt/ztncui/src/etc \
    && ln -s /app/ztncui/src/etc /opt/ztncui/src/etc \
    && ln -s /app/ztncui/src/.env /opt/ztncui/src/.env
WORKDIR /app
COPY patch/*.js patch/*.sh ./
VOLUME ["/app/dist","/app/ztncui","/var/lib/zerotier-one","/app/config"]
HEALTHCHECK --interval=10s --timeout=8s --start-period=30s --retries=3 \
    CMD ["/bin/sh", "/app/healthcheck.sh"]
CMD ["flock", "-n", "-F", "/var/lib/zerotier-one", "/bin/bash", "/app/entrypoint.sh"]
