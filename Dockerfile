# ============================================================
# Fiberus Development Container
# ============================================================
# Includes: Haxe compiler (fiberus target, LOCAL prebuilt binary),
#           Neko + haxelib (distro), fiberus runtime, GCC toolchain.
#
# The Haxe fork is NOT cloned from GitHub — the current branch only
# exists locally. The image copies the prebuilt binary from haxe/haxe
# and stdlib from haxe/std, so every rebuild snapshots the exact
# local toolchain. Build the fork locally before building this image.
#
# Build:
#   ./build-docker.sh
#   -- or --
#   docker build -t fiberus -f docker-setup/Dockerfile .
#
# Run:
#   docker run --rm -it \
#     --security-opt seccomp=unconfined \
#     --ulimit memlock=-1:-1 \
#     -v $(pwd):/workspace \
#     fiberus
#
# Persistent compile cache (optional):
#   docker run --rm -it \
#     --security-opt seccomp=unconfined \
#     --ulimit memlock=-1:-1 \
#     -v $(pwd):/workspace \
#     -v fiberus-cache:/opt/fiberus-cache \
#     fiberus
#
# IMPORTANT: --security-opt seccomp=unconfined is required for io_uring.
# IMPORTANT: --ulimit memlock=-1:-1 is required for io_uring registered buffers
#            (the runtime pins 1024 x 128KB = 128MB per worker thread).
# Platform:  linux/amd64 only (x86_64 assembly + io_uring)
# ============================================================

FROM ubuntu:24.04

LABEL maintainer="fiberus"
LABEL description="Fiberus development environment with Haxe compiler, runtime, and GCC toolchain"

ARG DEBIAN_FRONTEND=noninteractive

# Runtime + build dependencies.
# GCC is required: fiberus compiles generated C code at user build time.
# The distro `haxe` package supplies haxelib + neko + mbedtls/pcre2 shared
# libs the fork binary links against; /usr/local/bin/haxe shadows /usr/bin/haxe.
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    binutils \
    make \
    liburing-dev \
    libjemalloc-dev \
    haxe \
    && rm -rf /var/lib/apt/lists/*

# Local prebuilt Haxe fork (binary + stdlib)
COPY haxe/haxe /opt/haxe/haxe
COPY haxe/std /opt/haxe/std
RUN chmod +x /opt/haxe/haxe && \
    ln -s /opt/haxe/haxe /usr/local/bin/haxe && \
    mkdir -p /usr/local/share/haxe && \
    ln -s /opt/haxe/std /usr/local/share/haxe/std

ENV HAXE_STD_PATH=/usr/local/share/haxe/std

# Set up haxelib
RUN mkdir -p /opt/haxelib && haxelib setup /opt/haxelib

# Copy fiberus runtime source
COPY fiberus/ /opt/fiberus/

# Register fiberus as a haxelib dev library
RUN haxelib dev fiberus /opt/fiberus

# Verify installation
RUN set -ex; \
    haxe --version; \
    neko -version; \
    gcc --version | head -1; \
    haxelib list

# Entrypoint script for runtime checks and warp10 registration
COPY docker-setup/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["bash"]
