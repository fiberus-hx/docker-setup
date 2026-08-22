# docker-setup

Docker development environment for Fiberus. Builds a self-contained image with the Haxe compiler (fiberus target, **local prebuilt binary** — the current fork branch exists only locally, nothing is cloned), the Fiberus runtime, GCC toolchain, and all native dependencies. Mount your project into `/workspace` and compile directly inside the container.

**Prerequisite:** build the Haxe fork locally first — the image copies `haxe/haxe` and `haxe/std` from the repo. Every image rebuild snapshots the exact current local toolchain (~2 min; rebuild after toolchain changes).

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

Single-stage build from `ubuntu:24.04`:

- Installs build dependencies (gcc, g++, binutils, make, liburing-dev, libjemalloc-dev) plus the distro `haxe` package, which supplies `haxelib`, neko, and the mbedtls/pcre2 shared libs the fork binary links against.
- Copies the **local prebuilt** Haxe fork binary (`haxe/haxe`) and stdlib (`haxe/std`) to `/opt/haxe`; the `/usr/local/bin/haxe` symlink shadows the distro `/usr/bin/haxe`.
- Copies the `fiberus/` runtime source to `/opt/fiberus`, registers it as a haxelib dev library, and sets the entrypoint to `docker-entrypoint.sh`.

## Files

```
docker-setup/
  Dockerfile              Single-stage build (local prebuilt haxe + fiberus runtime)
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
| `IMAGE_NAME` | `fiberus` | Docker image name |
| `IMAGE_TAG` | `latest` | Docker image tag |

The script preflights that `haxe/haxe` and `haxe/std` exist and aborts with instructions if not.

```bash
# Custom image name
IMAGE_NAME=my-fiberus IMAGE_TAG=v1 ./build-docker.sh
```

Or build directly with `docker build`:

```bash
docker build \
  --platform linux/amd64 \
  -f docker-setup/Dockerfile \
  -t fiberus .
```

## Run Examples

**Basic usage:**

```bash
docker run --rm -it \
  --security-opt seccomp=unconfined \
  --ulimit memlock=-1:-1 \
  -v $(pwd)/your-project:/workspace \
  fiberus
```

**Building this repo's `libraries/` in the container** — two traps:

1. Do NOT mount the repo root at `/workspace`: haxelib picks up the host `.haxelib/` (a local repo beats the global config) and its dev paths are host-absolute. Mount `libraries/` only.
2. `fib_sqlite3/lib/*.c` include `../../../fiberus/runtime/*.h`, so the layout `<root>/libraries/<lib>` + `<root>/fiberus/` must exist — recreate it with a symlink to the baked-in runtime:

```bash
docker run --rm -it \
  --security-opt seccomp=unconfined \
  --ulimit memlock=-1:-1 \
  -v $(pwd)/libraries:/workspace/libraries \
  fiberus \
  bash -c "ln -s /opt/fiberus /workspace/fiberus && cd /workspace/libraries/alexandria && make release && make test"
```

The container runs as root — `chown -R $(id -u):$(id -g)` mounted build outputs (`bin/`, `test/bin/`, `client/`) afterwards.

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
| Haxe compiler | `/opt/haxe/haxe` | Local prebuilt fork binary (fiberus target) |
| Haxe std library | `/opt/haxe/std` | Includes fiberus std lib |
| haxelib | `/usr/bin/haxelib` | From the distro `haxe` package (the distro `/usr/bin/haxe` is shadowed) |
| Fiberus runtime | `/opt/fiberus/` | Registered as haxelib dev library |
| GCC/G++ | System packages | Required: fiberus compiles generated C at user build time |
| Neko | System package | Required by haxelib (pulled in by the `haxe` package) |
| liburing-dev | System package | io_uring headers |
| libjemalloc-dev | System package | Memory allocator |

## .dockerignore

The build context is the project root. The `.dockerignore` excludes everything except `fiberus/` (runtime source, minus obj/lib), `haxe/haxe` + `haxe/std` (local prebuilt compiler), and `docker-setup/docker-entrypoint.sh`.

## Platform

Linux x86_64 (`linux/amd64`) only. The Fiberus runtime uses x86_64 assembly for fiber context switching and Linux io_uring for async I/O. The image is not compatible with ARM or macOS Docker.
