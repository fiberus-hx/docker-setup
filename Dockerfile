# ============================================================
# Fiberus Development Container
# ============================================================
# Includes: Haxe compiler (fiberus target), Neko, fiberus runtime,
#           GCC toolchain, and pre-compiled runtime libraries.
#
# Build:
#   ./build-docker.sh
#   -- or --
#   docker build -t fiberus -f docker-setup/Dockerfile .
#   docker build --build-arg HAXE_BRANCH=fiberus -t fiberus -f docker-setup/Dockerfile .
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

# --- Stage 1: Build runtime cache ---
FROM ubuntu:24.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive

# Install build dependencies (GCC toolchain + OCaml/opam for compiling Haxe)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    binutils \
    neko \
    liburing-dev \
    libmbedtls-dev \
    libjemalloc-dev \
    neko-dev \
    ca-certificates \
    curl \
    git \
    opam \
    bubblewrap \
    libpcre2-dev \
    zlib1g-dev \
    pkg-config \
    m4 \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# Initialize opam with default repository (needed for OCaml compiler + deps)
RUN opam init --disable-sandboxing --yes && \
    opam switch create haxe 5.2.1 --yes && \
    opam clean --yes

# Clone Haxe source
ARG HAXE_BRANCH=typedis
RUN git clone --depth 1 --branch "${HAXE_BRANCH}" --recurse-submodules \
        https://github.com/fiberus-hx/haxe.git /tmp/haxe-src

# Install Haxe OCaml dependencies and build
RUN set -ex; \
    eval $(opam env --switch=haxe); \
    cd /tmp/haxe-src; \
    opam pin add haxe . --no-action --yes; \
    opam install haxe --deps-only --yes; \
    make haxe; \
    make tools; \
    # Install into /opt/haxe
    mkdir -p /opt/haxe; \
    cp haxe haxelib /opt/haxe/; \
    cp -r std /opt/haxe/std; \
    chmod +x /opt/haxe/haxe /opt/haxe/haxelib; \
    # Symlink into PATH
    ln -s /opt/haxe/haxe /usr/local/bin/haxe; \
    ln -s /opt/haxe/haxelib /usr/local/bin/haxelib; \
    # Set up std library path
    mkdir -p /usr/local/share/haxe; \
    ln -s /opt/haxe/std /usr/local/share/haxe/std; \
    # Cleanup build artifacts to reduce image size
    rm -rf /tmp/haxe-src; \
    opam clean --yes



# --- Stage 2: Final runtime image ---
FROM ubuntu:24.04

LABEL maintainer="fiberus"
LABEL description="Fiberus development environment with Haxe compiler, runtime, and GCC toolchain"

ARG DEBIAN_FRONTEND=noninteractive

# Install runtime + build dependencies
# GCC is required: fiberus compiles generated C code at user build time
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    binutils \
    neko \
    liburing-dev \
    libjemalloc-dev \
    make \
    && rm -rf /var/lib/apt/lists/*

# Copy Haxe compiler and std lib
COPY --from=builder /opt/haxe /opt/haxe
COPY --from=builder /usr/local/bin/haxe /usr/local/bin/haxe
COPY --from=builder /usr/local/bin/haxelib /usr/local/bin/haxelib
COPY --from=builder /usr/local/share/haxe /usr/local/share/haxe

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
