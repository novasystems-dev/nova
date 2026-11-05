#!/usr/bin/env bash
# ==========================================================
# Nova Distribution Installer (M11.6)
# Installs novac, orbit, nova-fmt, nova-lsp, nova-lint,
# standard library, and the nova-rt runtime headers.
# ==========================================================
set -euo pipefail

PREFIX="${1:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/nova"

echo "=========================================================="
echo "  NOVA TOOLCHAIN INSTALLER"
echo "  Target Prefix: $PREFIX"
echo "=========================================================="

mkdir -p "$BIN_DIR" "$LIB_DIR/runtime" "$LIB_DIR/std"

echo "-> Installing compiler binaries into $BIN_DIR..."
cp -f bin/novac "$BIN_DIR/novac"
cp -f bin/orbit "$BIN_DIR/orbit"
cp -f bin/nova-fmt "$BIN_DIR/nova-fmt"
cp -f bin/nova-lsp "$BIN_DIR/nova-lsp"
cp -f bin/nova-lint "$BIN_DIR/nova-lint"
chmod +x "$BIN_DIR/novac" "$BIN_DIR/orbit" "$BIN_DIR/nova-fmt" "$BIN_DIR/nova-lsp" "$BIN_DIR/nova-lint"

echo "-> Installing runtime headers into $LIB_DIR/runtime..."
cp -f runtime/nova_rt.h "$LIB_DIR/runtime/nova_rt.h"
cp -f runtime/nova_rt.c "$LIB_DIR/runtime/nova_rt.c"

echo "-> Installing standard library into $LIB_DIR/std..."
cp -f std/*.nova "$LIB_DIR/std/"

echo "=========================================================="
echo "🎉 Nova Toolchain successfully installed!"
echo "   Ensure '$BIN_DIR' is in your PATH:"
echo "   export PATH=\"$BIN_DIR:\$PATH\""
echo "=========================================================="
