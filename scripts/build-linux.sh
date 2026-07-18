#!/usr/bin/env bash
#
# build-linux.sh — Build libnode (Node.js shared library) on Linux
#
# Usage:  VERSION=22.0.0 ARCH=x64 ./build-linux.sh
#
# The script downloads the Node.js source for the given version,
# configures it with --shared, builds, and packages the output
# into libnode-linux-{arch}.tar.gz.
#
# For x86, this script is designed to run inside an i386 Docker container
# (native 32-bit environment). No cross-compilation flags needed.
#
# Environment variables:
#   VERSION   – Node.js version to build (semver, e.g. 22.0.0)
#   MAJOR     – Major version (derived from VERSION if not set)
#   ARCH      – Target architecture: x64 (default) or x86
#

set -euo pipefail

# ── Input validation ────────────────────────────────────────────────
VERSION="${VERSION:?Missing VERSION environment variable (e.g. 22.0.0)}"
MAJOR="${MAJOR:-$(echo "$VERSION" | cut -d. -f1)}"
ARCH="${ARCH:-x64}"

if [ "${ARCH}" != "x64" ] && [ "${ARCH}" != "x86" ]; then
    echo "::error::ARCH must be 'x64' or 'x86', got '${ARCH}'"
    exit 1
fi

SRC_DIR="node-v${VERSION}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/tmp/libnode-install}"

echo "==> Building libnode for Node.js v${VERSION} (major: ${MAJOR}, arch: ${ARCH})"

# ── Install system dependencies ─────────────────────────────────────
echo "==> Installing system build dependencies..."
export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" -eq 0 ]; then
    # Running as root (Docker container)
    apt-get update -qq
    apt-get install -y -qq \
        python3 make gcc g++ git nasm curl xz-utils
elif command -v sudo &>/dev/null; then
    # Running as non-root with sudo access (host)
    sudo apt-get update -qq
    PACKAGES=(python3 make gcc g++ nasm curl xz-utils file)
    if [ "${ARCH}" = "x86" ]; then
        PACKAGES+=( gcc-multilib g++-multilib )
    fi
    sudo apt-get install -y -qq "${PACKAGES[@]}"
else
    echo "::error::Cannot install dependencies: neither root nor sudo"
    exit 1
fi

# ── Download and extract source ─────────────────────────────────────
if [ ! -d "${SRC_DIR}" ]; then
    echo "==> Downloading Node.js v${VERSION} source..."
    curl -fsSL "https://nodejs.org/dist/v${VERSION}/node-v${VERSION}.tar.xz" \
        -o "node-v${VERSION}.tar.xz"
    echo "==> Extracting source..."
    tar -xf "node-v${VERSION}.tar.xz"
fi

cd "${SRC_DIR}"

# ── Apply OpenSSL patch for x86 ─────────────────────────────────────
if [ "${ARCH}" = "x86" ]; then
    echo "==> Patching OpenSSL .S assembly files..."
    for f in $(find deps/openssl -type f -name '*.S'); do
        sed -i "s/%ifdef/#ifdef/" "$f"
        sed -i "s/%endif/#endif/" "$f"
    done

    # Enable SSE and native optimizations (no -m32; native 32-bit inside Docker)
    export CXXFLAGS="-march=native -mfpmath=sse"
    export CFLAGS="-march=native -mfpmath=sse"
fi

# ── Configure with --shared ─────────────────────────────────────────
# For x86 inside Docker: native 32-bit, no --dest-cpu needed.
# For x64: standard build.
echo "==> Configuring with --shared (arch: ${ARCH})..."
./configure --shared --prefix="${INSTALL_PREFIX}"

# ── Build ───────────────────────────────────────────────────────────
echo "==> Building (this may take a while)..."
make -j"$(nproc 2>/dev/null || echo 4)"

# ── Collect artifacts ───────────────────────────────────────────────
echo "==> Collecting artifacts..."
cd ..
mkdir -p dist

if [ -d "${SRC_DIR}/out/Release" ]; then
    cp "${SRC_DIR}/out/Release"/libnode.so* dist/ 2>/dev/null || true
fi

# ── Package into release archive ────────────────────────────────────
ARCHIVE_NAME="libnode-linux-${ARCH}.tar.gz"
echo "==> Packaging artifacts into ${ARCHIVE_NAME}..."
tar -czf "${ARCHIVE_NAME}" -C dist .
echo "    Created: ${ARCHIVE_NAME} ($(du -h "${ARCHIVE_NAME}" | cut -f1))"

echo "==> Build complete! Archive ready: ${ARCHIVE_NAME}"
ls -la "${ARCHIVE_NAME}"

echo "==> Done."
