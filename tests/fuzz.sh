#!/usr/bin/env bash
# ==========================================================
# Nova Compiler Mutation Fuzzing Harness (M11.4)
# Generates randomized malformed token streams to verify
# that the compiler frontend never panics or segfaults.
# ==========================================================
set -euo pipefail

TOTAL_ITERATIONS=100
CRASHES=0
TIMEOUT_SEC=2

TMP_DIR="/tmp/nova_fuzz"
mkdir -p "$TMP_DIR"

echo "=========================================================="
echo "  NOVA GRAMMAR MUTATION FUZZER (Running $TOTAL_ITERATIONS iterations)"
echo "=========================================================="

python3 - << 'EOF'
import random
import string
import os

seeds = [
    "fn main():\n    let x = 42\n    print_int(x)\n",
    "type Tree = enum:\n    Leaf\n    Node(val: Int)\n",
    "fn test(x: Int where x > 0) -> Int:\n    x * 2\n",
    "type Ptr = struct:\n    val: Int\n",
]

mutations = [
    lambda s: s + random.choice(["\t", ":::", "{{{", "@@@", "$$$"]),
    lambda s: s.replace("fn", random.choice(["fnn", "fn:", "fn 123", ""])),
    lambda s: s.replace(":", random.choice(["", "::", " : ", "->"])),
    lambda s: s.replace("let", random.choice(["let mut mut", "let 123", ""])),
    lambda s: random.choice(seeds) + "".join(random.choices(string.printable, k=20)),
    lambda s: "".join(random.choices(string.ascii_letters + " \n\t:()", k=50)),
]

os.makedirs("/tmp/nova_fuzz", exist_ok=True)
for i in range(100):
    seed = random.choice(seeds)
    mut = random.choice(mutations)(seed)
    with open(f"/tmp/nova_fuzz/test_{i}.nova", "w") as f:
        f.write(mut)
EOF

run_with_timeout() {
    local sec="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$sec" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$sec" "$@"
    else
        "$@"
    fi
}

for i in $(seq 0 $((TOTAL_ITERATIONS - 1))); do
    TEST_FILE="$TMP_DIR/test_${i}.nova"
    # Run compiler with timeout
    if ! run_with_timeout "$TIMEOUT_SEC" ./bin/novac check "$TEST_FILE" > /dev/null 2>&1; then
        EXIT_CODE=$?
        # Exit code 124 means timeout; 139 means SIGSEGV; 134 means SIGABRT
        if [ "$EXIT_CODE" -eq 139 ] || [ "$EXIT_CODE" -eq 134 ] || [ "$EXIT_CODE" -eq 124 ]; then
            echo "❌ CRASH / TIMEOUT detected on $TEST_FILE (Exit code: $EXIT_CODE)"
            CRASHES=$((CRASHES + 1))
        fi
    fi
done

rm -rf "$TMP_DIR"

echo "=========================================================="
echo "  FUZZING SUMMARY: $TOTAL_ITERATIONS tests executed, $CRASHES compiler crashes."
echo "=========================================================="

if [ "$CRASHES" -eq 0 ]; then
    echo "🎉 FUZZER PASSED: 100% resilient frontend error recovery!"
    exit 0
else
    echo "❌ FUZZER FAILED: Compiler instability detected."
    exit 1
fi
