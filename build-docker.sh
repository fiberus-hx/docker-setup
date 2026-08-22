#!/bin/bash
set -e

# ============================================================
# Fiberus Docker Image Build Script
# ============================================================
# Builds the Fiberus development Docker image. The Haxe compiler
# is the LOCAL prebuilt fork binary (haxe/haxe + haxe/std) — the
# current fork branch only exists locally, so nothing is cloned.
# Build the fork locally before building the image.
#
# Usage:
#   ./build-docker.sh
#
# Environment variables:
#   IMAGE_NAME     - Docker image name (default: fiberus)
#   IMAGE_TAG      - Docker image tag (default: latest)
# ============================================================

IMAGE_NAME="${IMAGE_NAME:-fiberus}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- Preflight: local haxe fork binary must exist ----
if [ ! -x "$PROJECT_ROOT/haxe/haxe" ] || [ ! -d "$PROJECT_ROOT/haxe/std" ]; then
    echo "ERROR: $PROJECT_ROOT/haxe/haxe (or haxe/std) missing." >&2
    echo "Build the haxe fork locally first, then re-run." >&2
    exit 1
fi

# ---- Build the Docker image ----
echo "==> Building Docker image ${IMAGE_NAME}:${IMAGE_TAG}..."
echo "    Platform:      linux/amd64"
echo "    Haxe binary:   $PROJECT_ROOT/haxe/haxe ($(date -r "$PROJECT_ROOT/haxe/haxe" +%F))"
echo "    Build context: $PROJECT_ROOT"
echo ""

docker build \
    --platform linux/amd64 \
    -f "$SCRIPT_DIR/Dockerfile" \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    "$PROJECT_ROOT"

echo ""
echo "==> Done. Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "Run with:"
echo "    docker run --rm -it \\"
echo "      --security-opt seccomp=unconfined \\"
echo "      --ulimit memlock=-1:-1 \\"
echo "      -v \$(pwd)/your-project:/workspace \\"
echo "      ${IMAGE_NAME}:${IMAGE_TAG}"
