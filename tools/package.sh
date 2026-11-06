#!/usr/bin/env bash
# ==============================================================================
# Nova Systems Programming Language - Release Packaging Engine
# Builds separate Runtime and Full-Dev distributions for multi-platform releases
# ==============================================================================
set -euo pipefail

VERSION="${1:-v0.1.0}"
TARGET="${2:-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)}"
DIST_DIR="dist"

echo "=========================================================="
echo "  NOVA RELEASE PACKAGING ENGINE"
echo "  Version: $VERSION | Target: $TARGET"
echo "=========================================================="

mkdir -p "$DIST_DIR"

# 1. Package Runtime-Only Distribution
RUNTIME_PKG_NAME="nova-runtime-${VERSION}-${TARGET}"
RUNTIME_DIR="${DIST_DIR}/${RUNTIME_PKG_NAME}"
rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"

echo "-> Creating Runtime package: ${RUNTIME_PKG_NAME}..."
cp -r runtime "$RUNTIME_DIR/"
cp -r std "$RUNTIME_DIR/"
cp LICENSE README.md "$RUNTIME_DIR/" 2>/dev/null || true

tar -czf "${DIST_DIR}/${RUNTIME_PKG_NAME}.tar.gz" -C "$DIST_DIR" "$RUNTIME_PKG_NAME"
echo "   Artifact created: ${DIST_DIR}/${RUNTIME_PKG_NAME}.tar.gz"
rm -rf "$RUNTIME_DIR"

# 2. Package Full Developer Toolchain Distribution
FULL_PKG_NAME="nova-dev-full-${VERSION}-${TARGET}"
FULL_DIR="${DIST_DIR}/${FULL_PKG_NAME}"
rm -rf "$FULL_DIR"
mkdir -p "$FULL_DIR"

echo "-> Creating Full Developer package: ${FULL_PKG_NAME}..."
mkdir -p "$FULL_DIR/bin"
# Copy binaries dereferencing symlinks so archives are self-contained
cp -L bin/novac "$FULL_DIR/bin/" 2>/dev/null || true
cp -L bin/novac.exe "$FULL_DIR/bin/" 2>/dev/null || true
cp -L bin/orbit "$FULL_DIR/bin/" 2>/dev/null || true
cp -L bin/orbit.exe "$FULL_DIR/bin/" 2>/dev/null || true
cp -L bin/nova-repl "$FULL_DIR/bin/" 2>/dev/null || true
cp -L bin/nova-lsp "$FULL_DIR/bin/" 2>/dev/null || true
cp -L bin/nova-fmt "$FULL_DIR/bin/" 2>/dev/null || true
cp -L bin/nova-lint "$FULL_DIR/bin/" 2>/dev/null || true
cp -L bin/nova-doc "$FULL_DIR/bin/" 2>/dev/null || true
cp -L bin/nova-doc.exe "$FULL_DIR/bin/" 2>/dev/null || true
chmod +x "$FULL_DIR/bin/"* 2>/dev/null || true

cp -r runtime "$FULL_DIR/"
cp -r std "$FULL_DIR/"
cp -r examples "$FULL_DIR/"
cp -r editors "$FULL_DIR/" 2>/dev/null || true
cp -r docs "$FULL_DIR/" 2>/dev/null || true
cp install.sh "$FULL_DIR/" 2>/dev/null || true
cp orbit.toml Orbit.lock LICENSE README.md "$FULL_DIR/" 2>/dev/null || true

tar -czf "${DIST_DIR}/${FULL_PKG_NAME}.tar.gz" -C "$DIST_DIR" "$FULL_PKG_NAME"
echo "   Artifact created: ${DIST_DIR}/${FULL_PKG_NAME}.tar.gz"
rm -rf "$FULL_DIR"

# 3. Generate SHA-256 Checksums
echo "-> Computing cryptographic SHA-256 integrity checksums..."
cd "$DIST_DIR"

compute_sha256() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file"
    else
        openssl dgst -sha256 "$file" | awk '{print $NF, "'"$file"'"}'
    fi
}

compute_sha256 "nova-runtime-${VERSION}-${TARGET}.tar.gz" > "nova-runtime-${VERSION}-${TARGET}.tar.gz.sha256"
compute_sha256 "nova-dev-full-${VERSION}-${TARGET}.tar.gz" > "nova-dev-full-${VERSION}-${TARGET}.tar.gz.sha256"
cat "nova-runtime-${VERSION}-${TARGET}.tar.gz.sha256" >> "SHA256SUMS.txt"
cat "nova-dev-full-${VERSION}-${TARGET}.tar.gz.sha256" >> "SHA256SUMS.txt"
cd ..

echo "=========================================================="
echo "✅ PACKAGING COMPLETED SUCCESSFULLY!"
echo "   - ${DIST_DIR}/${RUNTIME_PKG_NAME}.tar.gz"
echo "   - ${DIST_DIR}/${FULL_PKG_NAME}.tar.gz"
echo "   - ${DIST_DIR}/SHA256SUMS.txt"
echo "=========================================================="
