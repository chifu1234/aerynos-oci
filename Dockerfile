# syntax=docker/dockerfile:1
#
# AerynOS container image
#
# External images: StageX only (filesystem, musl, busybox).
# Built here: download moss, install packages, slim rootfs, final scratch image.
#
# Local build (recommended):
#   ./build.sh
# Equivalent:
#   docker buildx build --allow security.insecure --platform linux/amd64 \
#     -t aerynos:unstable --load .
#
# Platform: linux/amd64 only (StageX + AerynOS packages are x86_64).
#

# ---------------------------------------------------------------------------
# Build args (global)
# ---------------------------------------------------------------------------
ARG STAGEX_TAG=sx2026.06.0
ARG STAGEX_REGISTRY=docker.io/stagex
ARG MOSS_VERSION=v0.26.1
ARG REPO_NAME=unstable
ARG REPO_URL=https://cdn.aerynos.dev/stream/unstable/x86_64/stone.index
# Default package set (gawk omitted; rootfs script installs a pure-bash command-not-found helper)
ARG PACKAGES=bash moss ca-certificates uutils-coreutils curl sed grep

# ---------------------------------------------------------------------------
# StageX tooling only — external images, not built here
# ---------------------------------------------------------------------------
FROM ${STAGEX_REGISTRY}/core-filesystem:${STAGEX_TAG} AS sx-filesystem
FROM ${STAGEX_REGISTRY}/core-musl:${STAGEX_TAG} AS sx-musl
FROM ${STAGEX_REGISTRY}/core-busybox:${STAGEX_TAG} AS sx-busybox

# ---------------------------------------------------------------------------
# Bootstrap: StageX base + moss (downloaded in-Dockerfile, not from host)
# ---------------------------------------------------------------------------
FROM scratch AS bootstrap

COPY --from=sx-filesystem . /
COPY --from=sx-musl . /
COPY --from=sx-busybox . /

ENV PATH=/usr/bin:/usr/sbin:/bin:/sbin

ARG MOSS_VERSION=v0.26.1
# Remote ADD: no host-side moss binary, no extra download image
ADD https://github.com/AerynOS/os-tools/releases/download/${MOSS_VERSION}/moss.tar.gz /tmp/moss.tar.gz
RUN tar -xzf /tmp/moss.tar.gz -C /usr/bin \
    && rm -f /tmp/moss.tar.gz \
    && chmod +x /usr/bin/moss \
    && moss version

COPY build-aerynos-rootfs.sh /usr/bin/build-aerynos-rootfs
RUN chmod +x /usr/bin/build-aerynos-rootfs

# ---------------------------------------------------------------------------
# Rootfs: moss install (namespace triggers need security.insecure)
# ---------------------------------------------------------------------------
FROM bootstrap AS rootfs

ARG REPO_NAME=unstable
ARG REPO_URL=https://cdn.aerynos.dev/stream/unstable/x86_64/stone.index
ARG PACKAGES=bash moss ca-certificates uutils-coreutils curl sed grep

ENV REPO_NAME=${REPO_NAME} \
    REPO_URL=${REPO_URL} \
    PACKAGES=${PACKAGES} \
    ROOTFS=/aerynos-rootfs \
    MOSS_CACHE=/var/cache/moss \
    OUT_TAR=/rootfs.tar

# Moss install triggers need user namespaces → BuildKit security.insecure
# (see ./build.sh or the GitHub release workflow).
RUN --network=default --security=insecure \
    build-aerynos-rootfs

# ---------------------------------------------------------------------------
# Unpack rootfs tar into a directory tree (preserves moss hardlinks for COPY)
# ---------------------------------------------------------------------------
FROM bootstrap AS unpack

COPY --from=rootfs /rootfs.tar /tmp/rootfs.tar
RUN mkdir -p /out \
    && tar -C /out -xf /tmp/rootfs.tar \
    && rm -f /tmp/rootfs.tar

# ---------------------------------------------------------------------------
# Final image (scratch + unpacked rootfs)
# ---------------------------------------------------------------------------
FROM scratch AS final

LABEL org.opencontainers.image.title="AerynOS" \
      org.opencontainers.image.description="AerynOS container image (unstable stream), bootstrapped via StageX" \
      org.opencontainers.image.url="https://aerynos.dev/" \
      org.opencontainers.image.source="https://github.com/AerynOS/os-tools" \
      org.opencontainers.image.vendor="AerynOS" \
      org.opencontainers.image.licenses="MPL-2.0"

COPY --from=unpack /out /

ENV PATH=/usr/bin:/usr/sbin \
    LANG=C.UTF-8

CMD ["/usr/bin/bash"]
