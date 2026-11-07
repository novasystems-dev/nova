#!/usr/bin/env bash
set -euo pipefail
mkdir -p /tmp 2>/dev/null || true

echo "=========================================================="
echo "  NOVA COMPREHENSIVE TEST SUITE & VERIFICATION HARNESS"
echo "=========================================================="

PASSED=0
FAILED=0

run_test() {
    local name="$1"
    local cmd="$2"
    echo -n "-> Running: $name ... "
    local out
    if out=$(eval "$cmd" 2>&1); then
        echo "PASSED"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED"
        echo "   [ERROR]: $out"
        FAILED=$((FAILED + 1))
    fi
}

run_rejection_test() {
    local name="$1"
    local cmd="$2"
    echo -n "-> Running (negative check): $name ... "
    local out
    if ! out=$(eval "$cmd" 2>&1); then
        echo "REJECTED AS EXPECTED (PASSED)"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED (Unexpected success)"
        echo "   [UNEXPECTED OUTPUT]: $out"
        FAILED=$((FAILED + 1))
    fi
}

# 1. Typecheck & SMT proof checks on core examples
run_test "Check 01_hello.nova" "./bin/novac check examples/01_hello.nova"
run_test "Check 02_refinements_z3.nova" "./bin/novac check examples/02_refinements_z3.nova"
run_test "Check 03_perceus_tree.nova" "./bin/novac check examples/03_perceus_tree.nova"
run_test "Check 04_concurrency_channels.nova" "./bin/novac check examples/04_concurrency_channels.nova"
run_test "Check 06_snake_game.nova" "./bin/novac check examples/06_snake_game.nova"
run_test "Check 07_network_http_server.nova" "./bin/novac check examples/07_network_http_server.nova"
run_test "Check 08_traits_and_baremetal.nova" "./bin/novac check examples/08_traits_and_baremetal.nova"
run_test "Check 09_std_industrial.nova" "./bin/novac check examples/09_std_industrial.nova"
run_test "Check stage1/src/types.nova" "./bin/novac check stage1/src/types.nova"
run_test "Check stage1/src/lexer.nova" "./bin/novac check stage1/src/lexer.nova"
run_test "Check stage1/src/parser.nova" "./bin/novac check stage1/src/parser.nova"
run_test "Check stage1/src/checker.nova" "./bin/novac check stage1/src/checker.nova"
run_test "Check stage1/src/codegen_c.nova" "./bin/novac check stage1/src/codegen_c.nova"
run_test "Check stage1/src/optimizer.nova" "./bin/novac check stage1/src/optimizer.nova"
run_test "Check stage1/src/main.nova" "./bin/novac check stage1/src/main.nova"

# 2. Standard Library checks
run_test "Check std/vec.nova" "./bin/novac check std/vec.nova"
run_test "Check std/map.nova" "./bin/novac check std/map.nova"
run_test "Check std/string.nova" "./bin/novac check std/string.nova"
run_test "Check std/io.nova" "./bin/novac check std/io.nova"
run_test "Check std/sync.nova" "./bin/novac check std/sync.nova"
run_test "Check std/fs.nova" "./bin/novac check std/fs.nova"
run_test "Check std/net.nova" "./bin/novac check std/net.nova"
run_test "Check std/json.nova" "./bin/novac check std/json.nova"
run_test "Check std/os.nova" "./bin/novac check std/os.nova"
run_test "Check std/math.nova" "./bin/novac check std/math.nova"
run_test "Check std/time.nova" "./bin/novac check std/time.nova"
run_test "Check std/crypto.nova" "./bin/novac check std/crypto.nova"
run_test "Check std/http.nova" "./bin/novac check std/http.nova"
run_test "Check std/collections.nova" "./bin/novac check std/collections.nova"
run_test "Check std/collections_adv.nova" "./bin/novac check std/collections_adv.nova"
run_test "Check std/crypto_adv.nova" "./bin/novac check std/crypto_adv.nova"
run_test "Check std/storage.nova" "./bin/novac check std/storage.nova"
run_test "Check std/db.nova" "./bin/novac check std/db.nova"
run_test "Check std/encoding.nova" "./bin/novac check std/encoding.nova"

# 3. Negative safety tests (Z3 SMT proof rejection)
run_rejection_test "Reject division by unproven zero (05_bad_division.nova)" "./bin/novac check examples/05_bad_division.nova"

# 4. Native code execution
run_test "Execute 01_hello.out" "./bin/novac run examples/01_hello.nova"
run_test "Execute 02_refinements_z3.out" "./bin/novac run examples/02_refinements_z3.nova"
run_test "Execute 03_perceus_tree.out" "./bin/novac run examples/03_perceus_tree.nova"
run_test "Execute 04_concurrency_channels.out" "./bin/novac run examples/04_concurrency_channels.nova"
run_test "Execute 08_traits_and_baremetal.out" "./bin/novac run examples/08_traits_and_baremetal.nova"
run_test "Execute 09_std_industrial.out" "./bin/novac run examples/09_std_industrial.nova"
run_test "Execute test_os_primitives.out" "./bin/novac run tests/test_os_primitives.nova"
run_test "Execute test_super_libraries.out" "./bin/novac run tests/test_super_libraries.nova"
run_test "Execute test_pure_nova_libraries.out" "./bin/novac run tests/test_pure_nova_libraries.nova"
run_test "Execute test_colossus.out" "./bin/novac run tests/test_colossus.nova"

# 5. Intermediate Representations & Codegen
run_test "Dump HIR (--dump-hir)" "./bin/novac --dump-hir examples/01_hello.nova"
run_test "Dump MIR (--dump-mir)" "./bin/novac --dump-mir examples/01_hello.nova"
run_test "Emit LLVM IR (--emit-llvm)" "./bin/novac --emit-llvm examples/01_hello.nova"
run_test "Emit C99 (--emit-c)" "./bin/novac --emit-c examples/01_hello.nova"

get_sha256() {
    local target="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$target" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$target" | awk '{print $1}'
    else
        openssl dgst -sha256 "$target" | awk '{print $NF}'
    fi
}

WIN_LIBS=""
if [[ "${OSTYPE:-}" == "msys"* ]] || [[ "${OSTYPE:-}" == "cygwin"* ]] || [[ "$(uname -s)" == *"MINGW"* ]]; then
    WIN_LIBS="-lws2_32"
fi

# 6. Tooling checks
run_test "Orbit capability audit" "./bin/orbit audit"
run_test "Orbit lockfile generation (orbit lock)" "./bin/orbit lock"
run_test "Interactive REPL evaluation pipeline" "printf 'let x = 21\nx * 2\n:quit\n' | ./bin/nova-repl | grep -q '42'"
run_test "Nova-fmt formatter" "./bin/nova-fmt examples/*.nova std/*.nova"
run_test "Nova-lint linter" "./bin/nova-lint examples/*.nova std/*.nova"
run_test "Nova-doc generator execution" "./bin/nova-doc >/dev/null"

# 7. Bootstrapping verification
run_test "Fixed-point hash equality (novac-2 vs novac-3)" "[ $(get_sha256 bin/novac-2) = $(get_sha256 bin/novac-3) ]"
run_test "Standalone C99 Genesis snapshot build (Zero Haskell)" "gcc -O3 -std=c99 -I./runtime bootstrap/novac_bootstrap.c runtime/nova_rt.c -lpthread -lm $WIN_LIBS -o /tmp/novac_c99 && /tmp/novac_c99 >/dev/null && rm -f /tmp/novac_c99 /tmp/novac_c99.exe"

# 8. Compiler Fuzzing & Benchmarks
run_test "Grammar mutation fuzzer (100 runs)" "./tests/fuzz.sh"
run_test "Benchmark suite execution" "./benchmarks/run_benchmarks.sh"

# Cleanup generated test binaries
rm -f *.out *.out.exe

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
