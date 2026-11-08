#!/usr/bin/env bash
# ==========================================================
# Nova High-Performance Benchmark Suite (M11.5)
# Measures compiler throughput, execution latency, and
# memory efficiency across canonical benchmarks.
# ==========================================================
set -euo pipefail

# Ensure /tmp directories exist across POSIX and Windows drive letters
mkdir -p /tmp /d/tmp /c/tmp D:/tmp C:/tmp 2>/dev/null || true

echo "=========================================================="
echo "  NOVA BENCHMARK RUNNER"
echo "=========================================================="

BENCH_FILES=(
    "tests/benchmarks/01_perceus_allocation.nv"
    "tests/benchmarks/02_arithmetic_throughput.nv"
    "tests/benchmarks/03_channel_concurrency.nv"
)

get_time_ms() {
    if date +%s%N 2>/dev/null | grep -vq 'N'; then
        echo $(( $(date +%s%N) / 1000000 ))
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import time; print(int(time.time() * 1000))"
    else
        echo $(( $(date +%s) * 1000 ))
    fi
}

for file in "${BENCH_FILES[@]}"; do
    echo "----------------------------------------------------------"
    echo "-> Benchmarking: $file"
    
    # Measure build time
    START_BUILD=$(get_time_ms)
    BUILD_LOG=$(./bin/novac build "$file" 2>&1) || {
        echo "Build failed for $file:"
        echo "$BUILD_LOG"
        exit 1
    }
    END_BUILD=$(get_time_ms)
    BUILD_MS=$(( END_BUILD - START_BUILD ))
    echo "   Build Time:     ${BUILD_MS} ms"
    
    # Measure execution time
    BIN_NAME="$(basename "$(basename "$file" .nova)" .nv).out"
    TARGET_EXEC="./$BIN_NAME"
    if [ -f "${TARGET_EXEC}.exe" ]; then
        TARGET_EXEC="${TARGET_EXEC}.exe"
    elif [ -f "./${BIN_NAME}.exe" ]; then
        TARGET_EXEC="./${BIN_NAME}.exe"
    elif [ -f "${BIN_NAME}.exe" ]; then
        TARGET_EXEC="./${BIN_NAME}.exe"
    elif [ -f "$BIN_NAME" ]; then
        TARGET_EXEC="./$BIN_NAME"
    fi

    if [ ! -f "$TARGET_EXEC" ]; then
        echo "Error: Output binary '$TARGET_EXEC' not found after build!"
        echo "$BUILD_LOG"
        exit 1
    fi

    START_RUN=$(get_time_ms)
    "$TARGET_EXEC" > /dev/null
    END_RUN=$(get_time_ms)
    RUN_MS=$(( END_RUN - START_RUN ))
    echo "   Execution Time: ${RUN_MS} ms"
    rm -f "$BIN_NAME" "${BIN_NAME}.exe"
done

echo "----------------------------------------------------------"
echo "🎉 ALL BENCHMARKS COMPLETED SUCCESSFULLY!"
