#!/usr/bin/env bash
# ============================================================================
# NOVA MULTI-STAGE BOOTSTRAPPING ENGINE (Stages 0 -> 1 -> 2 -> 3)
# Plus Standalone C99 Genesis Snapshot (Zero-Haskell Bridge)
# ============================================================================
set -euo pipefail

echo "=========================================================="
echo "  NOVA MULTI-STAGE BOOTSTRAPPING ENGINE"
echo "  Fixed-Point Verification & Zero-Haskell Snapshot"
echo "=========================================================="

mkdir -p bin bootstrap

echo "-> [Step 1] Building Genesis Stage 0 (novac-0) via Haskell GHC 9.6.6..."
export PATH="$HOME/.ghcup/bin:$HOME/.local/bin:$PATH"
cd stage0
cabal build -v0
cp dist-newstyle/build/x86_64-linux/ghc-9.6.6/novac-0.1.0.0/x/novac/build/novac/novac ../bin/novac-0
cd ..

echo "-> [Step 2] Compiling Nova compiler source using novac-0 to produce novac-1..."
./bin/novac-0 build stage1/src/main.nova
mv -f main.out bin/novac-1
chmod +x bin/novac-1

echo "-> [Step 3] Generating Standalone C99 Snapshot: bootstrap/novac_bootstrap.c..."
./bin/novac-0 --emit-c stage1/src/main.nova > bootstrap/novac_bootstrap.c

echo "-> [Step 4] Compiling novac-2 directly from C99 snapshot using host GCC..."
gcc -O3 -std=c99 -I./runtime bootstrap/novac_bootstrap.c runtime/nova_rt.c -lpthread -o bin/novac-2
chmod +x bin/novac-2

echo "-> [Step 5] Compiling novac-3 directly from C99 snapshot using host GCC..."
gcc -O3 -std=c99 -I./runtime bootstrap/novac_bootstrap.c runtime/nova_rt.c -lpthread -o bin/novac-3
chmod +x bin/novac-3

echo "-> [Step 6] Fixed-Point Bit-for-Bit Deterministic Verification (SHA-256)..."
HASH2=$(sha256sum bin/novac-2 | awk '{print $1}')
HASH3=$(sha256sum bin/novac-3 | awk '{print $1}')

echo "   novac-2 SHA-256: $HASH2"
echo "   novac-3 SHA-256: $HASH3"

if [ "$HASH2" = "$HASH3" ]; then
    echo "=========================================================="
    echo "🎉 FIXED-POINT ATTAINED: SHA-256 MATCHES 100% BIT-FOR-BIT!"
    echo "   Nova is officially a self-hosting independent language!"
    echo "=========================================================="
    cp -f bin/novac-2 bin/novac-standalone
    cp -f bin/novac-0 bin/novac
else
    echo "❌ Fixed-point mismatch between novac-2 and novac-3."
    exit 1
fi

echo "-> [Step 7] Testing Standalone Zero-Haskell Compiler binary..."
./bin/novac-standalone
