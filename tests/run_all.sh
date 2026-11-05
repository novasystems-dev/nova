#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo "  NOVA COMPREHENSIVE TEST SUITE & VERIFICATION HARNESS"
echo "=========================================================="

PASSED=0
FAILED=0

run_test() {
    local name="$1"
    local cmd="$2"
    echo -n "-> Running: $name ... "
    if eval "$cmd" > /dev/null 2>&1; then
        echo "PASSED"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED"
        FAILED=$((FAILED + 1))
    fi
}

run_rejection_test() {
    local name="$1"
    local cmd="$2"
    echo -n "-> Running (negative check): $name ... "
    if ! eval "$cmd" > /dev/null 2>&1; then
        echo "REJECTED AS EXPECTED (PASSED)"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED (Unexpected success)"
        FAILED=$((FAILED + 1))
    fi
}

# 1. Typecheck & SMT proof checks on core examples
run_test "Check 01_hello.nova" "./bin/novac check examples/01_hello.nova"
run_test "Check 02_refinements_z3.nova" "./bin/novac check examples/02_refinements_z3.nova"
run_test "Check 03_perceus_tree.nova" "./bin/novac check examples/03_perceus_tree.nova"
run_test "Check 04_concurrency_channels.nova" "./bin/novac check examples/04_concurrency_channels.nova"
run_test "Check 06_snake_game.nova" "./bin/novac check examples/06_snake_game.nova"
run_test "Check stage1/src/main.nova" "./bin/novac check stage1/src/main.nova"

# 2. Standard Library checks
run_test "Check std/vec.nova" "./bin/novac check std/vec.nova"
run_test "Check std/map.nova" "./bin/novac check std/map.nova"
run_test "Check std/string.nova" "./bin/novac check std/string.nova"
run_test "Check std/io.nova" "./bin/novac check std/io.nova"

# 3. Negative safety tests (Z3 SMT proof rejection)
run_rejection_test "Reject division by unproven zero (05_bad_division.nova)" "./bin/novac check examples/05_bad_division.nova"

# 4. Native code execution
run_test "Execute 01_hello.out" "./bin/novac run examples/01_hello.nova"
run_test "Execute 02_refinements_z3.out" "./bin/novac run examples/02_refinements_z3.nova"
run_test "Execute 03_perceus_tree.out" "./bin/novac run examples/03_perceus_tree.nova"
run_test "Execute 04_concurrency_channels.out" "./bin/novac run examples/04_concurrency_channels.nova"

# 5. Intermediate Representations & Codegen
run_test "Dump HIR (--dump-hir)" "./bin/novac --dump-hir examples/01_hello.nova"
run_test "Dump MIR (--dump-mir)" "./bin/novac --dump-mir examples/01_hello.nova"
run_test "Emit LLVM IR (--emit-llvm)" "./bin/novac --emit-llvm examples/01_hello.nova"
run_test "Emit C99 (--emit-c)" "./bin/novac --emit-c examples/01_hello.nova"

# 6. Tooling checks
run_test "Orbit capability audit" "./bin/orbit audit"
run_test "Nova-fmt formatter" "./bin/nova-fmt examples/*.nova std/*.nova"
run_test "Nova-lint linter" "./bin/nova-lint examples/*.nova std/*.nova"

# 7. Bootstrapping verification
run_test "Fixed-point hash equality (novac-2 vs novac-3)" "[ $(sha256sum bin/novac-2 | awk '{print $1}') = $(sha256sum bin/novac-3 | awk '{print $1}') ]"

# 8. Compiler Fuzzing & Benchmarks
run_test "Grammar mutation fuzzer (100 runs)" "./tests/fuzz.sh"
run_test "Benchmark suite execution" "./benchmarks/run_benchmarks.sh"

echo "=========================================================="
echo "  TEST RESULTS: $PASSED PASSED, $FAILED FAILED"
echo "=========================================================="

if [ "$FAILED" -eq 0 ]; then
    echo "🎉 ALL VERIFICATION CHECKS PASSED!"
    exit 0
else
    echo "❌ SOME TESTS FAILED!"
    exit 1
fi
