#!/usr/bin/env bash
# Local builder for aerynos:unstable.
#
# Creates a Buildx builder with security.insecure (needed for moss install),
# builds the Dockerfile, loads the image, and runs a short smoke test.
#
# Usage:
#   ./build.sh
#   IMAGE_TAG=aerynos:base PACKAGES="pkgset-aeryn-base ..." ./build.sh
#   STAGEX_TAG=sx2026.06.0 MOSS_VERSION=v0.26.1 ./build.sh
#   CLEAN=0 ./build.sh          # reuse Buildx cache

set -euo pipefail

cd "$(dirname "$0")"

IMAGE_TAG="${IMAGE_TAG:-aerynos:unstable}"
BUILDER_NAME="${BUILDER_NAME:-aerynos-insecure}"
MOSS_VERSION="${MOSS_VERSION:-v0.26.1}"
STAGEX_TAG="${STAGEX_TAG:-sx2026.06.0}"
STAGEX_REGISTRY="${STAGEX_REGISTRY:-docker.io/stagex}"
REPO_NAME="${REPO_NAME:-unstable}"
REPO_URL="${REPO_URL:-https://cdn.aerynos.dev/stream/unstable/x86_64/stone.index}"
PACKAGES="${PACKAGES:-bash moss ca-certificates uutils-coreutils curl sed grep}"
PLATFORM="${PLATFORM:-linux/amd64}"
CLEAN="${CLEAN:-1}"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker is required to build ${IMAGE_TAG}" >&2
  exit 1
fi

ensure_builder() {
  if ! docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
    echo "==> Creating buildx builder ${BUILDER_NAME} (security.insecure)"
    docker buildx create \
      --name "${BUILDER_NAME}" \
      --driver docker-container \
      --buildkitd-flags '--allow-insecure-entitlement security.insecure' \
      --use
  else
    docker buildx use "${BUILDER_NAME}"
  fi
  docker buildx inspect --bootstrap >/dev/null
}

echo "==> Builder + platform ${PLATFORM}"
ensure_builder

BUILD_ARGS=(
  --builder "${BUILDER_NAME}"
  --allow security.insecure
  --platform "${PLATFORM}"
  --build-arg "STAGEX_TAG=${STAGEX_TAG}"
  --build-arg "STAGEX_REGISTRY=${STAGEX_REGISTRY}"
  --build-arg "MOSS_VERSION=${MOSS_VERSION}"
  --build-arg "REPO_NAME=${REPO_NAME}"
  --build-arg "REPO_URL=${REPO_URL}"
  --build-arg "PACKAGES=${PACKAGES}"
  --target final
  -t "${IMAGE_TAG}"
  --load
  .
)

if [ "${CLEAN}" = "1" ]; then
  echo "==> From-scratch build (no cache, pull StageX bases)"
  BUILD_ARGS=(--no-cache --pull "${BUILD_ARGS[@]}")
  docker rmi -f "${IMAGE_TAG}" 2>/dev/null || true
else
  echo "==> Incremental build (cache allowed)"
fi

echo "==> docker buildx build → ${IMAGE_TAG}"
docker buildx build "${BUILD_ARGS[@]}"

echo "==> Smoke-testing interactive bash in ${IMAGE_TAG}"
docker run --rm --platform "${PLATFORM}" "${IMAGE_TAG}" \
  /usr/bin/bash -lc 'source /usr/share/defaults/aeryn-stateless-shell-conf.sh; command -v sed; command -v grep; command -v curl; sed --version | head -1; curl -fsSI https://cdn.aerynos.dev/ 2>&1 | head -1; nonesuch_xyz_123 2>&1 | head -1; [ 1 -eq 1 ] && echo bracket_ok; echo SMOKE_OK'

echo "==> Done: ${IMAGE_TAG}"
echo "    Run: docker run --rm -it --platform ${PLATFORM} ${IMAGE_TAG}"
