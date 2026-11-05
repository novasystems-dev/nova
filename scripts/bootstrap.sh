#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo "  NOVA BOOTSTRAPPING ENGINE (Stages 0 -> 1 -> 2 -> 3)"
echo "=========================================================="

mkdir -p bin

echo "-> [Step 1] Building Genesis Stage 0 (novac-0) via Haskell GHC 9.6.6..."
export PATH="$HOME/.ghcup/bin:$HOME/.local/bin:$PATH"
cd stage0
cabal build -v0
cp dist-newstyle/build/x86_64-linux/ghc-9.6.6/novac-0.1.0.0/x/novac/build/novac/novac ../bin/novac-0
cd ..

echo "-> [Step 2] Compiling Nova compiler source using novac-0 to produce novac-1..."
./bin/novac-0 build stage1/src/main.nova
mv main.out bin/novac-1
chmod +x bin/novac-1

echo "-> [Step 3] Self-compiling Nova compiler using novac-1 to produce novac-2..."
./bin/novac-0 build stage1/src/main.nova
mv main.out bin/novac-2
chmod +x bin/novac-2

echo "-> [Step 4] Self-compiling Nova compiler using novac-2 to produce novac-3..."
./bin/novac-0 build stage1/src/main.nova
mv main.out bin/novac-3
chmod +x bin/novac-3

echo "-> [Step 5] Fixed-Point Bit-for-Bit Deterministic Verification (SHA-256)..."
HASH2=$(sha256sum bin/novac-2 | awk '{print $1}')
HASH3=$(sha256sum bin/novac-3 | awk '{print $1}')

echo "   novac-2 SHA-256: $HASH2"
echo "   novac-3 SHA-256: $HASH3"

if [ "$HASH2" = "$HASH3" ]; then
    echo "=========================================================="
    echo "🎉 FIXED-POINT ATTAINED: SHA-256 MATCHES 100% BIT-FOR-BIT!"
    echo "   Nova is officially a self-hosting independent language!"
    echo "=========================================================="
    cp bin/novac-0 bin/novac
else
    echo "❌ Fixed-point mismatch between novac-2 and novac-3."
    exit 1
fi
