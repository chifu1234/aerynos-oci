# AerynOS Docker image

Minimal [AerynOS](https://aerynos.dev/) container image, built from the official **unstable** package stream.

| | |
|--|--|
| **What you get** | `bash`, `moss`, `curl`, core utilities, CA certificates |
| **Bootstrap** | [StageX](https://stagex.tools/) only (`core-filesystem`, `core-musl`, `core-busybox`) |
| **Everything else** | Built inside the Dockerfile (moss download, package install, slim rootfs) |
| **Architecture** | `linux/amd64` (x86_64) |

## Quick start

```bash
chmod +x build.sh
./build.sh

docker run --rm -it --platform linux/amd64 aerynos:unstable
```

Inside the container:

```bash
moss sync -u
moss install nano
```

## Local build

`./build.sh` creates a Buildx builder that allows `security.insecure` (required for moss install), then builds and smoke-tests the image:

```bash
docker buildx build --allow security.insecure --platform linux/amd64 \
  -t aerynos:unstable --load .
```

### Why `security.insecure`?

Moss runs install triggers in Linux user namespaces. A normal `docker build` cannot grant that entitlement, so the script uses a dedicated builder:

```bash
docker buildx create --name aerynos-insecure \
  --driver docker-container \
  --buildkitd-flags '--allow-insecure-entitlement security.insecure'
```

### Options

```bash
# Custom image name and package set
IMAGE_TAG=aerynos:base \
  PACKAGES="pkgset-aeryn-base pkgset-aeryn-utilities" \
  ./build.sh

# Pin StageX / moss versions
STAGEX_TAG=sx2026.06.0 MOSS_VERSION=v0.26.1 ./build.sh
STAGEX_REGISTRY=quay.io/stagex ./build.sh

# Faster rebuild (reuse Buildx layer cache)
CLEAN=0 ./build.sh
```

**Default packages:** `bash moss ca-certificates uutils-coreutils curl sed grep`

`sed` and `grep` stay for shell scripts. `gawk` is not installed; the image uses a pure-bash “command not found” helper so interactive shells stay reliable without a large awk/ICU stack.

On Apple Silicon, the forced `linux/amd64` platform runs under emulation.

## Release on GitHub (tag → GHCR)

Publishing runs **only when you push a git tag**. Branch pushes do not build or push images.

Workflow: [`.github/workflows/release.yml`](.github/workflows/release.yml)

```bash
git tag v0.1.0
git push origin v0.1.0
```

| Published image | When |
|-----------------|------|
| `ghcr.io/<owner>/<repo>:<tag>` | Every git tag (for example `v0.1.0`) |
| `ghcr.io/<owner>/<repo>:latest` | Only for tags that start with `v` |

Layers are pushed with **zstd** compression. The workflow checks the registry manifest for `tar+zstd`, then pulls the image and runs a smoke test.

```bash
docker pull ghcr.io/<owner>/<repo>:v0.1.0
docker run --rm -it --platform linux/amd64 ghcr.io/<owner>/<repo>:v0.1.0
```

The job uses `packages: write` with the default `GITHUB_TOKEN`. For private packages, grant readers access in the GitHub package settings.

## How the Dockerfile is structured

| Stage | Role |
|-------|------|
| `sx-*` | StageX base layers only (external) |
| `bootstrap` | StageX + moss binary from GitHub releases |
| `rootfs` | `moss install` into a rootfs (`RUN --security=insecure`) |
| `unpack` | Extract the rootfs tar (keeps moss hardlinks) |
| `final` | Empty `scratch` image + rootfs contents |

You do **not** need a host-side `moss` binary or `rootfs.tar` in the build context.

## Image size

After install, `build-aerynos-rootfs.sh` slims the rootfs **before** packing the tar. That matters because moss stores file contents under `/.moss/assets` and hardlinks them into `/usr`; deletes must run on the real tree, then unused assets are garbage-collected.

| Metric | Typical value |
|--------|----------------|
| `docker images` size | ~95 MB |
| Compressed content | ~28 MB |
| Unique file payload | ~63 MiB |

What gets removed (high level): extra locales and docs, a duplicate `/usr/bin/[` binary, ICU and related host libraries, most gconv modules, systemd leftovers, gawk, moss download cache and local repo index. Curl keeps the libraries it actually needs to load.

**Note:** Files removed for size may still be listed in the moss package database. `moss install` still works against the configured repo URL; a full `moss` integrity check may want to restore stripped paths.

## Troubleshooting

| Problem | What to do |
|---------|------------|
| `granting entitlement security.insecure is not allowed` | Use `./build.sh`, not plain `docker build` |
| Wrong architecture / StageX pull fails | Use `linux/amd64` (the scripts set this) |
| Moss trigger / `EPERM` during install | Rootfs stage must use `--security=insecure` |
| `command_not_found_handle: maximum function nesting level exceeded` | Rebuild with the default package set and current slim script (pure-bash handler; keep `sed` and `grep`) |
| Image tag missing after a release | Confirm you pushed a **git tag**, not only a branch |

## Dependency updates (Renovate)

[`renovate.json`](renovate.json) keeps chore-style pins up to date:

| What | Where | How |
|------|--------|-----|
| GitHub Actions | `.github/workflows/*.yml` | `github-actions` manager (digest-pinned when possible) |
| StageX tag `sx…` | `Dockerfile`, `build.sh`, release workflow | regex + Docker Hub (`stagex/core-filesystem`) |
| moss release | same files | regex + GitHub Releases (`AerynOS/os-tools`) |
| `# syntax=docker/dockerfile:…` | `Dockerfile` | Docker image `docker/dockerfile` |

PRs are labeled `chore` / `dependencies`, use `chore(deps):` commits, and group related bumps (actions / StageX / moss).

**Required once per repo:** install the [Renovate GitHub App](https://github.com/apps/renovate) (or run self-hosted Renovate). The config file alone does not open PRs.

Not version-managed (by design): `PACKAGES=…` set, floating `unstable` stream URL, StageX registry host (`docker.io` vs `quay.io`).

## References

- [AerynOS](https://aerynos.dev/)
- [moss / os-tools](https://github.com/AerynOS/os-tools)
- [StageX](https://stagex.tools/) · [StageX docs](https://docs.stagex.tools/)
- Package stream: `https://cdn.aerynos.dev/stream/unstable/x86_64/stone.index`

---

*Documentation and project scaffolding were written with AI assistance (Grok / xAI), then reviewed for accuracy against the build scripts and workflow.*
