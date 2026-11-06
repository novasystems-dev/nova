#!/usr/bin/env bash
# ============================================================================
# NOVA OFFICIAL DISTRIBUTION PACKAGING ENGINE
# Builds binary tarball release with SHA-256 checksums
# ============================================================================
set -euo pipefail

VERSION="0.1.0"
TARGET="x86_64-linux"
DIST_NAME="nova-v${VERSION}-${TARGET}"
DIST_DIR="dist/${DIST_NAME}"
TARBALL="dist/${DIST_NAME}.tar.gz"

echo "=========================================================="
echo "  NOVA RELEASE DISTRIBUTION PACKAGER"
echo "  Version: $VERSION | Target: $TARGET"
echo "=========================================================="

echo "-> 1. Running comprehensive verification harness..."
./tests/run_all.sh

echo "-> 2. Preparing clean distribution staging tree at $DIST_DIR..."
rm -rf "dist"
mkdir -p "$DIST_DIR/bin" "$DIST_DIR/runtime" "$DIST_DIR/std" "$DIST_DIR/docs" "$DIST_DIR/editors" "$DIST_DIR/examples"

echo "-> 3. Collecting binary artifacts..."
cp -f bin/novac "$DIST_DIR/bin/"
cp -f bin/orbit "$DIST_DIR/bin/"
cp -f bin/nova-repl "$DIST_DIR/bin/"
cp -f bin/nova-fmt "$DIST_DIR/bin/"
cp -f bin/nova-lsp "$DIST_DIR/bin/"
cp -f bin/nova-lint "$DIST_DIR/bin/"
chmod +x "$DIST_DIR/bin/"*

echo "-> 4. Collecting runtime engine and standard library..."
cp -f runtime/nova_rt.h "$DIST_DIR/runtime/"
cp -f runtime/nova_rt.c "$DIST_DIR/runtime/"
cp -f std/*.nova "$DIST_DIR/std/"

echo "-> 5. Collecting documentation, editors, and examples..."
cp -f docs/*.md "$DIST_DIR/docs/"
cp -rf editors/* "$DIST_DIR/editors/"
cp -f examples/*.nova "$DIST_DIR/examples/"

echo "-> 6. Packaging project manifest and installer..."
cp -f install.sh "$DIST_DIR/"
cp -f Orbit.lock "$DIST_DIR/"
cp -f orbit.toml "$DIST_DIR/"
cp -f README.md "$DIST_DIR/"
cp -f LICENSE "$DIST_DIR/"

echo "-> 7. Creating release tarball: $TARBALL..."
tar -czf "$TARBALL" -C dist "$DIST_NAME"

echo "-> 8. Computing cryptographic SHA-256 checksum..."
sha256sum "$TARBALL" > "${TARBALL}.sha256"

echo "=========================================================="
echo "🎉 Release distribution package created successfully!"
echo "   Archive:  $TARBALL"
echo "   Checksum: $(cat "${TARBALL}.sha256")"
echo "=========================================================="
