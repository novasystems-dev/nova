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
cp -L bin/nova-runner "$FULL_DIR/bin/" 2>/dev/null || true
cp -L bin/nova-runner.exe "$FULL_DIR/bin/" 2>/dev/null || true

# Explicit fallback from tests/tools/ if bin/ symlinks failed on Windows
if [ ! -f "$FULL_DIR/bin/orbit" ] && [ ! -f "$FULL_DIR/bin/orbit.exe" ]; then
    cp tests/tools/orbit/orbit "$FULL_DIR/bin/" 2>/dev/null || cp tests/tools/orbit/orbit.exe "$FULL_DIR/bin/" 2>/dev/null || true
fi
if [ ! -f "$FULL_DIR/bin/nova-doc" ] && [ ! -f "$FULL_DIR/bin/nova-doc.exe" ]; then
    cp tests/tools/docgen/nova_doc "$FULL_DIR/bin/nova-doc" 2>/dev/null || cp tests/tools/docgen/nova_doc.exe "$FULL_DIR/bin/nova-doc.exe" 2>/dev/null || true
fi
if [ ! -f "$FULL_DIR/bin/nova-fmt" ]; then cp tests/tools/fmt/nova_fmt "$FULL_DIR/bin/nova-fmt" 2>/dev/null || true; fi
if [ ! -f "$FULL_DIR/bin/nova-lint" ]; then cp tests/tools/lint/nova_lint "$FULL_DIR/bin/nova-lint" 2>/dev/null || true; fi
if [ ! -f "$FULL_DIR/bin/nova-repl" ]; then cp tests/tools/repl/nova_repl "$FULL_DIR/bin/nova-repl" 2>/dev/null || true; fi
if [ ! -f "$FULL_DIR/bin/nova-lsp" ]; then cp tests/tools/lsp/nova_lsp "$FULL_DIR/bin/nova-lsp" 2>/dev/null || true; fi

chmod +x "$FULL_DIR/bin/"* 2>/dev/null || true

cp -r runtime "$FULL_DIR/"
cp -r std "$FULL_DIR/"
cp -r examples "$FULL_DIR/"
cp -r compiler "$FULL_DIR/" 2>/dev/null || true
cp -r compiler/docs "$FULL_DIR/docs" 2>/dev/null || true
cp install.sh install.ps1 install.bat "$FULL_DIR/" 2>/dev/null || true
cp orbit.toml Orbit.lock LICENSE README.md "$FULL_DIR/" 2>/dev/null || true

tar -czf "${DIST_DIR}/${FULL_PKG_NAME}.tar.gz" -C "$DIST_DIR" "$FULL_PKG_NAME"
echo "   Artifact created: ${DIST_DIR}/${FULL_PKG_NAME}.tar.gz"

# Also create standard zip package for Windows environments
if [[ "$TARGET" == *"windows"* ]] || command -v zip >/dev/null 2>&1 || python3 -c "import zipfile" 2>/dev/null; then
    echo "-> Creating Zip package for Windows compatibility..."
    python3 -c "
import zipfile, os
dist_dir = '$DIST_DIR'
pkg_name = '$FULL_PKG_NAME'
zip_path = os.path.join(dist_dir, pkg_name + '.zip')
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(os.path.join(dist_dir, pkg_name)):
        for f in files:
            full = os.path.join(root, f)
            rel = os.path.relpath(full, dist_dir)
            z.write(full, rel)
print('   Artifact created:', zip_path)
" 2>/dev/null || true
fi

rm -rf "$FULL_DIR"

# 3. Generate SHA-256 Checksums
echo "-> Computing cryptographic SHA-256 integrity checksums..."
cd "$DIST_DIR"

compute_sha256() {
    local file="$1"
    if [ ! -f "$file" ]; then return 0; fi
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

if [ -f "nova-dev-full-${VERSION}-${TARGET}.zip" ]; then
    compute_sha256 "nova-dev-full-${VERSION}-${TARGET}.zip" > "nova-dev-full-${VERSION}-${TARGET}.zip.sha256"
    cat "nova-dev-full-${VERSION}-${TARGET}.zip.sha256" >> "SHA256SUMS.txt"
fi
cd ..

echo "=========================================================="
echo "✅ PACKAGING COMPLETED SUCCESSFULLY!"
echo "   - ${DIST_DIR}/${RUNTIME_PKG_NAME}.tar.gz"
echo "   - ${DIST_DIR}/${FULL_PKG_NAME}.tar.gz"
echo "   - ${DIST_DIR}/SHA256SUMS.txt"
echo "=========================================================="
