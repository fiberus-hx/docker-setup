#!/bin/bash
set -e

# ============================================================
# Fiberus Docker Image Build Script
# ============================================================
# Builds the Fiberus development Docker image. The Haxe compiler
# is built from source inside the container (cloned from GitHub).
#
# Usage:
#   ./build-docker.sh
#
# Environment variables:
#   HAXE_BRANCH    - Git branch to build (default: fiberus)
#   IMAGE_NAME     - Docker image name (default: fiberus)
#   IMAGE_TAG      - Docker image tag (default: latest)
# ============================================================

IMAGE_NAME="${IMAGE_NAME:-fiberus}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
HAXE_BRANCH="${HAXE_BRANCH:-fiberus}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- Build the Docker image ----
echo "==> Building Docker image ${IMAGE_NAME}:${IMAGE_TAG}..."
echo "    Platform:      linux/amd64"
echo "    Haxe branch:   $HAXE_BRANCH"
echo "    Build context:  $PROJECT_ROOT"
echo ""

docker build \
    --platform linux/amd64 \
    --build-arg "HAXE_BRANCH=${HAXE_BRANCH}" \
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
