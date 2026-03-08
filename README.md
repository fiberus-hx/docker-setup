# docker-setup

Docker development environment for Fiberus. Builds a self-contained image with the Haxe compiler (fiberus target, compiled from source), the Fiberus runtime, GCC toolchain, and all native dependencies. Mount your project into `/workspace` and compile directly inside the container.

## Quick Start

```bash
# Build the image
cd docker-setup
./build-docker.sh

# Run with a project mounted
docker run --rm -it \
  --security-opt seccomp=unconfined \
  --ulimit memlock=-1:-1 \
  -v $(pwd)/your-project:/workspace \
  fiberus
```

## Architecture

The Dockerfile uses a two-stage build:

**Stage 1 (`builder`)** -- Installs the full OCaml/opam toolchain, clones the Haxe compiler source from `fiberus-hx/haxe` on GitHub, and builds it from source. The compiled `haxe` and `haxelib` binaries plus the standard library are installed to `/opt/haxe`.

**Stage 2 (final image)** -- Starts from a clean `ubuntu:24.04`. Installs only runtime/build dependencies (gcc, g++, neko, liburing-dev, libjemalloc-dev, make). Copies the built Haxe compiler from stage 1, copies the `fiberus/` runtime source, registers it as a haxelib dev library, and sets the entrypoint to `docker-entrypoint.sh`.

## Files

```
docker-setup/
  Dockerfile              Multi-stage build (builder + final image)
  build-docker.sh         Build script (wraps docker build with defaults)
  docker-entrypoint.sh    Runtime checks (kernel, seccomp, memlock)

.dockerignore             Build context filter (project root)
```

## Required Docker Flags

Both flags are **mandatory** for Fiberus to function:

| Flag | Reason |
|------|--------|
| `--security-opt seccomp=unconfined` | Docker's default seccomp profile blocks `io_uring_setup` (syscall 425). Fiberus uses io_uring for all async I/O. |
| `--ulimit memlock=-1:-1` | The runtime registers 1024 x 128KB = 128MB of pinned buffers per worker thread via `io_uring_register_buffers`. Docker's default memlock limit (64KB) causes registration to fail. |

## Build Options

The build script (`build-docker.sh`) accepts environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `HAXE_BRANCH` | `fiberus` | Git branch of `fiberus-hx/haxe` to build |
| `IMAGE_NAME` | `fiberus` | Docker image name |
| `IMAGE_TAG` | `latest` | Docker image tag |

```bash
# Build from a specific branch
HAXE_BRANCH=typedis ./build-docker.sh

# Custom image name
IMAGE_NAME=my-fiberus IMAGE_TAG=v1 ./build-docker.sh
```

Or build directly with `docker build`:

```bash
docker build \
  --platform linux/amd64 \
  --build-arg HAXE_BRANCH=fiberus \
  -f docker-setup/Dockerfile \
  -t fiberus .
```

## Run Examples

**Basic usage:**

```bash
docker run --rm -it \
  --security-opt seccomp=unconfined \
  --ulimit memlock=-1:-1 \
  -v $(pwd):/workspace \
  fiberus
```

**With persistent compile cache** (avoids re-compiling the runtime `.a` on each run):

```bash
docker run --rm -it \
  --security-opt seccomp=unconfined \
  --ulimit memlock=-1:-1 \
  -v $(pwd):/workspace \
  -v fiberus-cache:/opt/fiberus-cache \
  fiberus
```

## Entrypoint Checks

The entrypoint script (`docker-entrypoint.sh`) runs four checks before handing off to `CMD`:

1. **Config file** -- Creates `$HOME/.fiberus_config.xml` if missing, setting `FIBERUS_COMPILE_CACHE` to `/opt/fiberus-cache`.
2. **Kernel version** -- Warns if host kernel is older than 5.10 (minimum for io_uring).
3. **memlock ulimit** -- Warns if soft memlock limit is below 512MB.
4. **io_uring seccomp** -- Uses a Python3 one-liner to attempt `io_uring_setup` syscall (425 on x86_64). Warns if blocked by seccomp (EPERM/ENOSYS).

All checks are warnings only -- the container still starts, but Fiberus programs will fail at runtime if io_uring is unavailable.

## What's Included in the Image

| Component | Path | Notes |
|-----------|------|-------|
| Haxe compiler | `/opt/haxe/haxe`, `/opt/haxe/haxelib` | Built from source (fiberus target) |
| Haxe std library | `/opt/haxe/std` | Includes fiberus std lib |
| Fiberus runtime | `/opt/fiberus/` | Registered as haxelib dev library |
| GCC/G++ | System packages | Required: fiberus compiles generated C at user build time |
| Neko | System package | Required by haxelib |
| liburing-dev | System package | io_uring headers |
| libjemalloc-dev | System package | Memory allocator |

## .dockerignore

The build context is the project root. The `.dockerignore` excludes everything except `fiberus/` (runtime source, minus obj/lib) and `docker-setup/docker-entrypoint.sh`. The Haxe compiler is built from a GitHub clone inside the container, not copied from the host.

## Platform

Linux x86_64 (`linux/amd64`) only. The Fiberus runtime uses x86_64 assembly for fiber context switching and Linux io_uring for async I/O. The image is not compatible with ARM or macOS Docker.
