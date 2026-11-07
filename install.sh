#!/usr/bin/env bash
# ==========================================================
# Nova Distribution Universal Installer (v0.31.00)
# Supports both:
# 1. Online one-line install:
#    curl -fsSL https://raw.githubusercontent.com/novasystems-dev/nova/master/install.sh | bash
# 2. Local directory install:
#    ./install.sh [target_prefix]
# ==========================================================
set -euo pipefail

PREFIX="${1:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/nova"
CLEANUP_TMP=""

cleanup() {
    if [ -n "$CLEANUP_TMP" ] && [ -d "$CLEANUP_TMP" ]; then
        rm -rf "$CLEANUP_TMP"
    fi
}
trap cleanup EXIT

echo "=========================================================="
echo "  NOVA TOOLCHAIN UNIVERSAL INSTALLER"
echo "  Target Prefix: $PREFIX"
echo "=========================================================="

echo "-> Verifying system prerequisites..."
command -v gcc >/dev/null 2>&1 || { echo "⚠️  Warning: 'gcc' not found. GCC or Clang is required for native compilation."; }
command -v z3 >/dev/null 2>&1 || { echo "⚠️  Warning: 'z3' not found. Z3 SMT solver is recommended for refinement proofs."; }

# Determine source directory (local vs online curl | bash)
SRC_DIR=""
if [ -f "bin/novac" ] && [ -d "std" ] && [ -d "runtime" ]; then
    echo "-> Detected local Nova source/distribution directory."
    SRC_DIR="."
elif [ -f "../bin/novac" ] && [ -d "../std" ]; then
    SRC_DIR=".."
else
    echo "-> Running in online one-line mode. Fetching official release binary..."
    
    # Detect OS
    OS_RAW="$(uname -s)"
    case "$OS_RAW" in
        Linux*)  OS="linux" ;;
        Darwin*) OS="macos" ;;
        *)       OS="linux" ;;
    esac

    # Detect Architecture
    ARCH_RAW="$(uname -m)"
    case "$ARCH_RAW" in
        x86_64|amd64)   ARCH="x86_64" ;;
        aarch64|arm64)  ARCH="aarch64" ;;
        *)              ARCH="x86_64" ;;
    esac

    # Resolve latest release tag
    TAG="v0.31.00"
    if command -v curl >/dev/null 2>&1; then
        LATEST_TAG=$(curl -sI https://github.com/novasystems-dev/nova/releases/latest 2>/dev/null | grep -i "^location:" | awk -F'/' '{print $NF}' | tr -d '\r\n' || true)
        if [ -n "$LATEST_TAG" ]; then TAG="$LATEST_TAG"; fi
    fi

    ASSET_NAME="nova-dev-full-${TAG}-${OS}-${ARCH}.tar.gz"
    DOWNLOAD_URL="https://github.com/novasystems-dev/nova/releases/download/${TAG}/${ASSET_NAME}"
    
    TMP_DIR=$(mktemp -d -t nova-install-XXXXXX)
    CLEANUP_TMP="$TMP_DIR"
    TAR_FILE="$TMP_DIR/$ASSET_NAME"
    EXTRACT_DIR="$TMP_DIR/extracted"
    mkdir -p "$EXTRACT_DIR"

    DOWNLOAD_OK=false
    echo "   Attempting download: $DOWNLOAD_URL"
    if command -v curl >/dev/null 2>&1; then
        if curl -fSL --progress-bar "$DOWNLOAD_URL" -o "$TAR_FILE" 2>/dev/null; then
            DOWNLOAD_OK=true
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --show-progress "$DOWNLOAD_URL" -O "$TAR_FILE" 2>/dev/null; then
            DOWNLOAD_OK=true
        fi
    fi

    if [ "$DOWNLOAD_OK" = true ] && [ -f "$TAR_FILE" ]; then
        echo "   Extracting toolchain distribution..."
        tar -xzf "$TAR_FILE" -C "$EXTRACT_DIR"
        SUBDIR=$(find "$EXTRACT_DIR" -type f -name "novac" -exec dirname {} \; 2>/dev/null | head -n 1)
        if [ -n "$SUBDIR" ]; then
            SRC_DIR="$(dirname "$SUBDIR")"
        fi
    fi

    # Verify if precompiled binary actually runs on this host's CPU and glibc
    NEED_BOOTSTRAP=false
    if [ -z "$SRC_DIR" ] || [ ! -f "$SRC_DIR/bin/novac" ]; then
        NEED_BOOTSTRAP=true
    elif ! "$SRC_DIR/bin/novac" version >/dev/null 2>&1; then
        echo "   Note: Precompiled release asset requires a different CPU microarchitecture level."
        NEED_BOOTSTRAP=true
    fi

    # Fallback to source clone & fast Genesis bootstrap if binary incompatible or download unavailable
    if [ "$NEED_BOOTSTRAP" = true ]; then
        echo "-> Initiating Genesis C99 fast bootstrap tailored for your host CPU..."
        GIT_DIR="$TMP_DIR/nova_git"
        if [ ! -d "$GIT_DIR" ]; then
            git clone --depth 1 https://github.com/novasystems-dev/nova.git "$GIT_DIR" >/dev/null 2>&1
        fi
        mkdir -p "$GIT_DIR/bin"
        if command -v gcc >/dev/null 2>&1; then
            echo "   Bootstrapping native novac compiler from C99 snapshot..."
            gcc -O3 -std=c99 -I"$GIT_DIR/runtime" "$GIT_DIR/compiler/bootstrap/novac_bootstrap.c" "$GIT_DIR/runtime/nova_rt.c" -lpthread -lm -o "$GIT_DIR/bin/novac"
            # Build Orbit and tools tailored for host CPU
            if [ -f "$GIT_DIR/tests/tools/orbit/main.nv" ]; then
                echo "   Compiling native orbit package manager..."
                (cd "$GIT_DIR" && ./bin/novac build tests/tools/orbit/main.nv >/dev/null 2>&1 || true)
                if [ -f "$GIT_DIR/main.out" ]; then mv -f "$GIT_DIR/main.out" "$GIT_DIR/bin/orbit"; fi
            fi
            if [ -f "$GIT_DIR/tests/tools/docgen/main.nv" ]; then
                (cd "$GIT_DIR" && ./bin/novac build tests/tools/docgen/main.nv >/dev/null 2>&1 || true)
                if [ -f "$GIT_DIR/main.out" ]; then mv -f "$GIT_DIR/main.out" "$GIT_DIR/bin/nova-doc"; fi
            fi
            if [ -f "$GIT_DIR/tests/tools/runner/main.c" ]; then
                gcc -O2 -Wall "$GIT_DIR/tests/tools/runner/main.c" -o "$GIT_DIR/bin/nova-runner" 2>/dev/null || true
            fi
            if [ -f "$GIT_DIR/tests/tools/fmt/nova_fmt" ]; then cp -f "$GIT_DIR/tests/tools/fmt/nova_fmt" "$GIT_DIR/bin/nova-fmt"; fi
            if [ -f "$GIT_DIR/tests/tools/lsp/nova_lsp" ]; then cp -f "$GIT_DIR/tests/tools/lsp/nova_lsp" "$GIT_DIR/bin/nova-lsp"; fi
            if [ -f "$GIT_DIR/tests/tools/lint/nova_lint" ]; then cp -f "$GIT_DIR/tests/tools/lint/nova_lint" "$GIT_DIR/bin/nova-lint"; fi
            if [ -f "$GIT_DIR/tests/tools/repl/nova_repl" ]; then cp -f "$GIT_DIR/tests/tools/repl/nova_repl" "$GIT_DIR/bin/nova-repl"; fi
            SRC_DIR="$GIT_DIR"
        else
            echo "❌ Error: Precompiled binaries are incompatible with host and 'gcc' was not found to bootstrap."
            exit 1
        fi
    fi
fi

if [ -z "$SRC_DIR" ] || [ ! -f "$SRC_DIR/bin/novac" ]; then
    echo "❌ Error: Could not locate novac compiler binary."
    exit 1
fi

mkdir -p "$BIN_DIR" "$LIB_DIR/runtime" "$LIB_DIR/std" "$LIB_DIR/compiler"

echo "-> Installing compiler binaries into $BIN_DIR..."
for b in novac orbit nova-fmt nova-lsp nova-lint nova-repl nova-runner nova-doc; do
    if [ -f "$SRC_DIR/bin/$b" ]; then
        cp -f "$SRC_DIR/bin/$b" "$BIN_DIR/$b"
        chmod +x "$BIN_DIR/$b"
    fi
done

echo "-> Installing runtime headers into $LIB_DIR/runtime..."
if [ -d "$SRC_DIR/runtime" ]; then
    cp -rf "$SRC_DIR/runtime"/* "$LIB_DIR/runtime/"
fi

echo "-> Installing standard library into $LIB_DIR/std..."
if [ -d "$SRC_DIR/std" ]; then
    cp -rf "$SRC_DIR/std"/* "$LIB_DIR/std/"
fi

echo "-> Installing compiler specification modules into $LIB_DIR/compiler..."
if [ -d "$SRC_DIR/compiler" ]; then
    cp -rf "$SRC_DIR/compiler"/* "$LIB_DIR/compiler/"
fi

# Desktop & MIME registration
if [ -f "$SRC_DIR/assets/desktop/register_linux.sh" ] && command -v bash >/dev/null 2>&1; then
    echo "-> Registering desktop integration and file associations..."
    bash "$SRC_DIR/assets/desktop/register_linux.sh" >/dev/null 2>&1 || true
fi

# Check PATH
PATH_CONFIGURED=false
case ":$PATH:" in
    *":$BIN_DIR:"*) PATH_CONFIGURED=true ;;
esac

if [ "$PATH_CONFIGURED" = false ] && [ "$PREFIX" = "$HOME/.local" ]; then
    SHELL_PROFILE=""
    if [ -f "$HOME/.bashrc" ]; then
        SHELL_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.zshrc" ]; then
        SHELL_PROFILE="$HOME/.zshrc"
    elif [ -f "$HOME/.profile" ]; then
        SHELL_PROFILE="$HOME/.profile"
    fi

    if [ -n "$SHELL_PROFILE" ] && [ -w "$SHELL_PROFILE" ]; then
        if ! grep -q "$BIN_DIR" "$SHELL_PROFILE" 2>/dev/null; then
            echo "" >> "$SHELL_PROFILE"
            echo "# Nova Systems Programming Language" >> "$SHELL_PROFILE"
            echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$SHELL_PROFILE"
            echo "-> Added '$BIN_DIR' to $SHELL_PROFILE"
        fi
    fi
fi

echo "=========================================================="
echo "🎉 Nova Toolchain successfully installed!"
echo "   Installed Version:"
"$BIN_DIR/novac" version || true
if [ -f "$BIN_DIR/orbit" ]; then
    "$BIN_DIR/orbit" version || true
fi
echo "----------------------------------------------------------"
if [ "$PATH_CONFIGURED" = false ]; then
    echo "ℹ️  Run the following command to refresh your current shell:"
    echo "   export PATH=\"$BIN_DIR:\$PATH\""
else
    echo "✨ '$BIN_DIR' is already in your PATH."
fi
echo "=========================================================="
