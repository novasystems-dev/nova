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

echo "-> Verifying system prerequisites..."
command -v gcc >/dev/null 2>&1 || { echo "⚠️  Warning: 'gcc' not found. GCC or Clang is required for native compilation."; }
command -v z3 >/dev/null 2>&1 || { echo "⚠️  Warning: 'z3' not found. Z3 SMT solver is recommended for refinement proofs."; }

mkdir -p "$BIN_DIR" "$LIB_DIR/runtime" "$LIB_DIR/std"

echo "-> Installing compiler binaries into $BIN_DIR..."
cp -f bin/novac "$BIN_DIR/novac"
cp -f bin/orbit "$BIN_DIR/orbit"
cp -f bin/nova-fmt "$BIN_DIR/nova-fmt"
cp -f bin/nova-lsp "$BIN_DIR/nova-lsp"
cp -f bin/nova-lint "$BIN_DIR/nova-lint"
cp -f bin/nova-repl "$BIN_DIR/nova-repl"
if [ -f bin/nova-runner ]; then cp -f bin/nova-runner "$BIN_DIR/nova-runner"; fi
chmod +x "$BIN_DIR/novac" "$BIN_DIR/orbit" "$BIN_DIR/nova-fmt" "$BIN_DIR/nova-lsp" "$BIN_DIR/nova-lint" "$BIN_DIR/nova-repl"
if [ -f "$BIN_DIR/nova-runner" ]; then chmod +x "$BIN_DIR/nova-runner"; fi

echo "-> Registering desktop integration and .nova file association..."
if [ -f assets/desktop/register_linux.sh ]; then
    bash assets/desktop/register_linux.sh >/dev/null 2>&1 || true
fi

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
