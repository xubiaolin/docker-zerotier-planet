FROM alpine:3.20 AS builder

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

ENV TZ=Asia/Shanghai
ARG TAG=main
ARG ZEROTIER_REPO=https://github.com/zerotier/ZeroTierOne.git
ARG ZEROTIER_REF=main
ARG ZTNCUI_REPO=https://github.com/key-networks/ztncui.git
ARG ZTNCUI_REF=1b2284864de48d2dcae22582fff122fe24909c3d

WORKDIR /app

RUN set -eux; \
    apk add --no-cache --virtual .build-deps \
        build-base \
        cmake \
        curl \
        g++ \
        gcc \
        git \
        go \
        jq \
        linux-headers \
        make \
        nodejs \
        npm \
        openssl-dev \
        pkgconfig \
        python3

# Build ZeroTier from an explicit ref. TAG is kept for backward-compatible
# build arguments; release builds should pass ZEROTIER_REF directly.
RUN set -eux; \
    if [ "${ZEROTIER_REF}" = "main" ] && [ "${TAG}" != "main" ]; then \
        ZEROTIER_REF="${TAG}"; \
    fi; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; \
    . "$HOME/.cargo/env"; \
    git clone "${ZEROTIER_REPO}" ZeroTierOne; \
    cd ZeroTierOne; \
    ZEROTIER_COMMIT="$(git rev-parse --verify "${ZEROTIER_REF}^{commit}" 2>/dev/null || git rev-parse --verify "origin/${ZEROTIER_REF}^{commit}")"; \
    git checkout --detach "${ZEROTIER_COMMIT}"; \
    test "$(git rev-parse HEAD)" = "$(git rev-parse --verify HEAD)"; \
    echo "Using ZeroTier ref ${ZEROTIER_REF}: $(git rev-parse HEAD)"; \
    make ZT_SYMLINK=1; \
    make -j"$(nproc)"; \
    make install; \
    zerotier-one -d || true; \
    sleep 5s; \
    pkill -9 zerotier-one || true

# Build ztncui from an explicit, verified source commit.
RUN set -eux; \
    git clone --progress "${ZTNCUI_REPO}" ztncui; \
    cd /app/ztncui; \
    ZTNCUI_COMMIT="$(git rev-parse --verify "${ZTNCUI_REF}^{commit}" 2>/dev/null || git rev-parse --verify "origin/${ZTNCUI_REF}^{commit}")"; \
    git checkout --detach "${ZTNCUI_COMMIT}"; \
    test "$(git rev-parse HEAD)" = "${ZTNCUI_REF}"; \
    echo "Using ztncui commit: $(git rev-parse HEAD)"; \
    cd /app/ztncui/src; \
    npm config set registry https://registry.npmmirror.com; \
    npm install --global node-gyp; \
    npm install; \
    npm cache clean --force; \
    rm -rf /app/ztncui/.git /root/.npm

FROM alpine:3.20

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

WORKDIR /app

ENV API_PORT=3443 \
    FILE_KEY='' \
    FILE_SERVER_PORT=3000 \
    GH_MIRROR="https://mirror.ghproxy.com/" \
    IP_ADDR4='' \
    IP_ADDR6='' \
    TZ=Asia/Shanghai \
    ZT_PORT=9994

COPY --from=builder /app/ztncui /bak/ztncui
COPY --from=builder /var/lib/zerotier-one /bak/zerotier-one

COPY --from=builder /app/ZeroTierOne/zerotier-one /usr/sbin/zerotier-one
COPY ./patch/entrypoint.sh /app/entrypoint.sh
COPY ./patch/http_server.js /app/http_server.js
COPY ./patch/ztncui_admin.js /app/ztncui_admin.js

RUN set -eux; \
    apk add --no-cache --virtual .runtime-deps \
        curl \
        jq \
        nodejs \
        npm \
        openssl; \
    mkdir -p /app/config

VOLUME ["/app/dist", "/app/ztncui", "/var/lib/zerotier-one", "/app/config"]

CMD ["/bin/sh","/app/entrypoint.sh"]
