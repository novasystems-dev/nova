#!/usr/bin/env bash
# ==========================================================
# Nova High-Performance Benchmark Suite (M11.5)
# Measures compiler throughput, execution latency, and
# memory efficiency across canonical benchmarks.
# ==========================================================
set -euo pipefail

echo "=========================================================="
echo "  NOVA BENCHMARK RUNNER"
echo "=========================================================="

BENCH_FILES=(
    "benchmarks/01_perceus_allocation.nova"
    "benchmarks/02_arithmetic_throughput.nova"
    "benchmarks/03_channel_concurrency.nova"
)

for file in "${BENCH_FILES[@]}"; do
    echo "----------------------------------------------------------"
    echo "-> Benchmarking: $file"
    
    # Measure build time
    START_BUILD=$(date +%s%N)
    ./bin/novac build "$file" > /dev/null
    END_BUILD=$(date +%s%N)
    BUILD_MS=$(( (END_BUILD - START_BUILD) / 1000000 ))
    echo "   Build Time:     ${BUILD_MS} ms"
    
    # Measure execution time
    BIN_NAME="$(basename "$file" .nova).out"
    START_RUN=$(date +%s%N)
    ./"$BIN_NAME" > /dev/null
    END_RUN=$(date +%s%N)
    RUN_MS=$(( (END_RUN - START_RUN) / 1000000 ))
    echo "   Execution Time: ${RUN_MS} ms"
    rm -f "$BIN_NAME"
done

echo "----------------------------------------------------------"
echo "🎉 ALL BENCHMARKS COMPLETED SUCCESSFULLY!"
