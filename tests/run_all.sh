#!/usr/bin/env bash
set -euo pipefail
mkdir -p /tmp bin 2>/dev/null || true

WIN_LIBS=""
if [[ "${OSTYPE:-}" == "msys"* ]] || [[ "${OSTYPE:-}" == "cygwin"* ]] || [[ "$(uname -s)" == *"MINGW"* ]]; then
    WIN_LIBS="-lws2_32"
fi

if [ ! -f bin/novac ] && [ ! -f bin/novac.exe ]; then
    echo "-> Bootstrapping native novac compiler from C99 genesis snapshot..."
    gcc -O3 -std=c99 -I./runtime compiler/bootstrap/novac_bootstrap.c runtime/nova_rt.c -lpthread -lm $WIN_LIBS -o bin/novac
    if [ -f bin/novac.exe ]; then cp -f bin/novac.exe bin/novac; fi
fi

# Ensure test developer tools are available in bin/
if [ ! -f bin/orbit ] && [ -f tests/tools/orbit/orbit ]; then cp tests/tools/orbit/orbit bin/orbit; fi
if [ ! -f bin/orbit ] && [ -f tests/tools/orbit/main.nova ]; then ./bin/novac build tests/tools/orbit/main.nova >/dev/null 2>&1 || true; if [ -f main.out ]; then mv main.out bin/orbit; fi; if [ -f main.out.exe ]; then mv main.out.exe bin/orbit.exe; cp -f bin/orbit.exe bin/orbit 2>/dev/null || true; fi; fi
if [ ! -f bin/nova-doc ] && [ -f tests/tools/docgen/nova_doc ]; then cp tests/tools/docgen/nova_doc bin/nova-doc; fi
if [ ! -f bin/nova-doc ] && [ -f tests/tools/docgen/main.nova ]; then ./bin/novac build tests/tools/docgen/main.nova >/dev/null 2>&1 || true; if [ -f main.out ]; then mv main.out bin/nova-doc; fi; if [ -f main.out.exe ]; then mv main.out.exe bin/nova-doc.exe; cp -f bin/nova-doc.exe bin/nova-doc 2>/dev/null || true; fi; fi
if [ ! -f bin/nova-fmt ] && [ -f tests/tools/fmt/nova_fmt ]; then cp tests/tools/fmt/nova_fmt bin/nova-fmt; fi
if [ ! -f bin/nova-lint ] && [ -f tests/tools/lint/nova_lint ]; then cp tests/tools/lint/nova_lint bin/nova-lint; fi
if [ ! -f bin/nova-repl ] && [ -f tests/tools/repl/nova_repl ]; then cp tests/tools/repl/nova_repl bin/nova-repl; fi
if [ ! -f bin/nova-runner ] && [ -f tests/tools/runner/main.c ]; then gcc -O2 -Wall tests/tools/runner/main.c -o bin/nova-runner; fi
chmod +x bin/* 2>/dev/null || true

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
        echo "::error title=Test Failure - $name::$out"
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
        echo "::error title=Negative Test Failure - $name::$out"
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
run_test "Check 10_btree_database.nova" "./bin/novac check examples/10_btree_database.nova"
run_test "Check 11_bloom_filter_cache.nova" "./bin/novac check examples/11_bloom_filter_cache.nova"
run_test "Check 12_matrix_neural_network.nova" "./bin/novac check examples/12_matrix_neural_network.nova"
run_test "Check 13_compression_pipeline.nova" "./bin/novac check examples/13_compression_pipeline.nova"
run_test "Check 14_priority_task_scheduler.nova" "./bin/novac check examples/14_priority_task_scheduler.nova"
run_test "Check 15_cryptographic_vault.nova" "./bin/novac check examples/15_cryptographic_vault.nova"
run_test "Check 16_toml_config_engine.nova" "./bin/novac check examples/16_toml_config_engine.nova"
run_test "Check 17_unicode_scanner.nova" "./bin/novac check examples/17_unicode_scanner.nova"
run_test "Check 18_3d_graphics_pipeline.nova" "./bin/novac check examples/18_3d_graphics_pipeline.nova"
run_test "Check 19_bmp_image_generator.nova" "./bin/novac check examples/19_bmp_image_generator.nova"
run_test "Check 20_sha512_crypto_hasher.nova" "./bin/novac check examples/20_sha512_crypto_hasher.nova"
run_test "Check 21_wasm_emitter.nova" "./bin/novac check examples/21_wasm_emitter.nova"
run_test "Check 22_http2_frame_pipeline.nova" "./bin/novac check examples/22_http2_frame_pipeline.nova"
run_test "Check 23_sha3_keccak.nova" "./bin/novac check examples/23_sha3_keccak.nova"
run_test "Check 24_wav_audio_synth.nova" "./bin/novac check examples/24_wav_audio_synth.nova"
run_test "Check 25_spatial_kdtree.nova" "./bin/novac check examples/25_spatial_kdtree.nova"
run_test "Check compiler/types.nova" "./bin/novac check compiler/types.nova"
run_test "Check compiler/lexer.nova" "./bin/novac check compiler/lexer.nova"
run_test "Check compiler/parser.nova" "./bin/novac check compiler/parser.nova"
run_test "Check compiler/checker.nova" "./bin/novac check compiler/checker.nova"
run_test "Check compiler/codegen_c.nova" "./bin/novac check compiler/codegen_c.nova"
run_test "Check compiler/codegen_llvm.nova" "./bin/novac check compiler/codegen_llvm.nova"
run_test "Check compiler/codegen_cranelift.nova" "./bin/novac check compiler/codegen_cranelift.nova"
run_test "Check compiler/codegen_wasm.nova" "./bin/novac check compiler/codegen_wasm.nova"
run_test "Check compiler/x86_tables.nova" "./bin/novac check compiler/x86_tables.nova"
run_test "Check compiler/arm64_tables.nova" "./bin/novac check compiler/arm64_tables.nova"
run_test "Check compiler/riscv_tables.nova" "./bin/novac check compiler/riscv_tables.nova"
run_test "Check compiler/wasm_tables.nova" "./bin/novac check compiler/wasm_tables.nova"
run_test "Check compiler/optimizer.nova" "./bin/novac check compiler/optimizer.nova"
run_test "Check compiler/main.nova" "./bin/novac check compiler/main.nova"

# 1.1 Java-Style Modular Architecture (.nv) checks
run_test "Check enterprise_service/src/config/app_config.nv" "./bin/novac check examples/enterprise_service/src/config/app_config.nv"
run_test "Check enterprise_service/src/config/database_config.nv" "./bin/novac check examples/enterprise_service/src/config/database_config.nv"
run_test "Check enterprise_service/src/config/security_config.nv" "./bin/novac check examples/enterprise_service/src/config/security_config.nv"
run_test "Check enterprise_service/src/models/user.nv" "./bin/novac check examples/enterprise_service/src/models/user.nv"
run_test "Check enterprise_service/src/models/account.nv" "./bin/novac check examples/enterprise_service/src/models/account.nv"
run_test "Check enterprise_service/src/models/transaction.nv" "./bin/novac check examples/enterprise_service/src/models/transaction.nv"
run_test "Check enterprise_service/src/models/audit_log.nv" "./bin/novac check examples/enterprise_service/src/models/audit_log.nv"
run_test "Check enterprise_service/src/models/session.nv" "./bin/novac check examples/enterprise_service/src/models/session.nv"
run_test "Check enterprise_service/src/dto/api_response.nv" "./bin/novac check examples/enterprise_service/src/dto/api_response.nv"
run_test "Check enterprise_service/src/dto/auth_dto.nv" "./bin/novac check examples/enterprise_service/src/dto/auth_dto.nv"
run_test "Check enterprise_service/src/dto/account_dto.nv" "./bin/novac check examples/enterprise_service/src/dto/account_dto.nv"
run_test "Check enterprise_service/src/dto/transfer_dto.nv" "./bin/novac check examples/enterprise_service/src/dto/transfer_dto.nv"
run_test "Check enterprise_service/src/repository/user_repo.nv" "./bin/novac check examples/enterprise_service/src/repository/user_repo.nv"
run_test "Check enterprise_service/src/repository/account_repo.nv" "./bin/novac check examples/enterprise_service/src/repository/account_repo.nv"
run_test "Check enterprise_service/src/repository/transaction_repo.nv" "./bin/novac check examples/enterprise_service/src/repository/transaction_repo.nv"
run_test "Check enterprise_service/src/repository/audit_repo.nv" "./bin/novac check examples/enterprise_service/src/repository/audit_repo.nv"
run_test "Check enterprise_service/src/service/crypto_service.nv" "./bin/novac check examples/enterprise_service/src/service/crypto_service.nv"
run_test "Check enterprise_service/src/service/auth_service.nv" "./bin/novac check examples/enterprise_service/src/service/auth_service.nv"
run_test "Check enterprise_service/src/service/account_service.nv" "./bin/novac check examples/enterprise_service/src/service/account_service.nv"
run_test "Check enterprise_service/src/service/transfer_service.nv" "./bin/novac check examples/enterprise_service/src/service/transfer_service.nv"
run_test "Check enterprise_service/src/service/audit_service.nv" "./bin/novac check examples/enterprise_service/src/service/audit_service.nv"
run_test "Check enterprise_service/src/middleware/logger_middleware.nv" "./bin/novac check examples/enterprise_service/src/middleware/logger_middleware.nv"
run_test "Check enterprise_service/src/middleware/auth_guard.nv" "./bin/novac check examples/enterprise_service/src/middleware/auth_guard.nv"
run_test "Check enterprise_service/src/middleware/rate_limiter.nv" "./bin/novac check examples/enterprise_service/src/middleware/rate_limiter.nv"
run_test "Check enterprise_service/src/middleware/cors_filter.nv" "./bin/novac check examples/enterprise_service/src/middleware/cors_filter.nv"
run_test "Check enterprise_service/src/controllers/health_controller.nv" "./bin/novac check examples/enterprise_service/src/controllers/health_controller.nv"
run_test "Check enterprise_service/src/controllers/auth_controller.nv" "./bin/novac check examples/enterprise_service/src/controllers/auth_controller.nv"
run_test "Check enterprise_service/src/controllers/account_controller.nv" "./bin/novac check examples/enterprise_service/src/controllers/account_controller.nv"
run_test "Check enterprise_service/src/controllers/transfer_controller.nv" "./bin/novac check examples/enterprise_service/src/controllers/transfer_controller.nv"
run_test "Check enterprise_service/src/main.nv" "./bin/novac check examples/enterprise_service/src/main.nv"

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
run_test "Check std/bloom.nova" "./bin/novac check std/bloom.nova"
run_test "Check std/lru.nova" "./bin/novac check std/lru.nova"
run_test "Check std/queue.nova" "./bin/novac check std/queue.nova"
run_test "Check std/matrix.nova" "./bin/novac check std/matrix.nova"
run_test "Check std/hash.nova" "./bin/novac check std/hash.nova"
run_test "Check std/bigint.nova" "./bin/novac check std/bigint.nova"
run_test "Check std/uuid.nova" "./bin/novac check std/uuid.nova"
run_test "Check std/ansi.nova" "./bin/novac check std/ansi.nova"
run_test "Check std/uri.nova" "./bin/novac check std/uri.nova"
run_test "Check std/tar.nova" "./bin/novac check std/tar.nova"
run_test "Check std/compress.nova" "./bin/novac check std/compress.nova"
run_test "Check std/btree.nova" "./bin/novac check std/btree.nova"
run_test "Check std/regex.nova" "./bin/novac check std/regex.nova"
run_test "Check std/async.nova" "./bin/novac check std/async.nova"
run_test "Check std/aes.nova" "./bin/novac check std/aes.nova"
run_test "Check std/sha256.nova" "./bin/novac check std/sha256.nova"
run_test "Check std/chacha20.nova" "./bin/novac check std/chacha20.nova"
run_test "Check std/toml.nova" "./bin/novac check std/toml.nova"
run_test "Check std/csv.nova" "./bin/novac check std/csv.nova"
run_test "Check std/unicode.nova" "./bin/novac check std/unicode.nova"
run_test "Check std/math3d.nova" "./bin/novac check std/math3d.nova"
run_test "Check std/crypto_suite.nova" "./bin/novac check std/crypto_suite.nova"
run_test "Check std/image_bmp.nova" "./bin/novac check std/image_bmp.nova"
run_test "Check std/json_full.nova" "./bin/novac check std/json_full.nova"
run_test "Check std/xml.nova" "./bin/novac check std/xml.nova"
run_test "Check std/http2.nova" "./bin/novac check std/http2.nova"
run_test "Check std/dns.nova" "./bin/novac check std/dns.nova"
run_test "Check std/geometry.nova" "./bin/novac check std/geometry.nova"
run_test "Check std/physics2d.nova" "./bin/novac check std/physics2d.nova"
run_test "Check std/crypto_sha3.nova" "./bin/novac check std/crypto_sha3.nova"
run_test "Check std/sound_wav.nova" "./bin/novac check std/sound_wav.nova"
run_test "Check std/runtime/sys_linux.nova" "./bin/novac check std/runtime/sys_linux.nova"
run_test "Check std/runtime/perceus_alloc.nova" "./bin/novac check std/runtime/perceus_alloc.nova"
run_test "Check std/runtime/sys_windows.nova" "./bin/novac check std/runtime/sys_windows.nova"
run_test "Check compiler/backend/x86_64_enc.nova" "./bin/novac check compiler/backend/x86_64_enc.nova"
run_test "Check compiler/backend/elf64.nova" "./bin/novac check compiler/backend/elf64.nova"
run_test "Check compiler/backend/pe.nova" "./bin/novac check compiler/backend/pe.nova"
run_test "Check std/async_runtime.nova" "./bin/novac check std/async_runtime.nova"
run_test "Check std/colossus_web.nova" "./bin/novac check std/colossus_web.nova"
run_test "Check std/titan_db.nova" "./bin/novac check std/titan_db.nova"
run_test "Check std/aether_gfx.nova" "./bin/novac check std/aether_gfx.nova"

# 3. Negative safety tests (Z3 SMT proof rejection)
run_rejection_test "Reject division by unproven zero (05_bad_division.nova)" "./bin/novac check examples/05_bad_division.nova"

# 4. Native code execution
run_test "Execute 01_hello.out" "./bin/novac run examples/01_hello.nova"
run_test "Execute 02_refinements_z3.out" "./bin/novac run examples/02_refinements_z3.nova"
run_test "Execute 03_perceus_tree.out" "./bin/novac run examples/03_perceus_tree.nova"
run_test "Execute 04_concurrency_channels.out" "./bin/novac run examples/04_concurrency_channels.nova"
run_test "Execute 08_traits_and_baremetal.out" "./bin/novac run examples/08_traits_and_baremetal.nova"
run_test "Execute 09_std_industrial.out" "./bin/novac run examples/09_std_industrial.nova"
run_test "Execute 10_btree_database.out" "./bin/novac run examples/10_btree_database.nova"
run_test "Execute 11_bloom_filter_cache.out" "./bin/novac run examples/11_bloom_filter_cache.nova"
run_test "Execute 12_matrix_neural_network.out" "./bin/novac run examples/12_matrix_neural_network.nova"
run_test "Execute 13_compression_pipeline.out" "./bin/novac run examples/13_compression_pipeline.nova"
run_test "Execute 14_priority_task_scheduler.out" "./bin/novac run examples/14_priority_task_scheduler.nova"
run_test "Execute 15_cryptographic_vault.out" "./bin/novac run examples/15_cryptographic_vault.nova"
run_test "Execute 16_toml_config_engine.out" "./bin/novac run examples/16_toml_config_engine.nova"
run_test "Execute 17_unicode_scanner.out" "./bin/novac run examples/17_unicode_scanner.nova"
run_test "Execute 18_3d_graphics_pipeline.out" "./bin/novac run examples/18_3d_graphics_pipeline.nova"
run_test "Execute 19_bmp_image_generator.out" "./bin/novac run examples/19_bmp_image_generator.nova"
run_test "Execute 20_sha512_crypto_hasher.out" "./bin/novac run examples/20_sha512_crypto_hasher.nova"
run_test "Execute 21_wasm_emitter.out" "./bin/novac run examples/21_wasm_emitter.nova"
run_test "Execute 22_http2_frame_pipeline.out" "./bin/novac run examples/22_http2_frame_pipeline.nova"
run_test "Execute 23_sha3_keccak.out" "./bin/novac run examples/23_sha3_keccak.nova"
run_test "Execute 24_wav_audio_synth.out" "./bin/novac run examples/24_wav_audio_synth.nova"
run_test "Execute 25_spatial_kdtree.out" "./bin/novac run examples/25_spatial_kdtree.nova"
run_test "Execute test_bloom_filter.out" "./bin/novac run tests/test_bloom_filter.nova"
run_test "Execute test_btree_index.out" "./bin/novac run tests/test_btree_index.nova"
run_test "Execute test_matrix_algebra.out" "./bin/novac run tests/test_matrix_algebra.nova"
run_test "Execute test_lru_cache.out" "./bin/novac run tests/test_lru_cache.nova"
run_test "Execute test_cryptographic_suite.out" "./bin/novac run tests/test_cryptographic_suite.nova"
run_test "Execute test_os_primitives.out" "./bin/novac run tests/test_os_primitives.nova"
run_test "Execute test_super_libraries.out" "./bin/novac run tests/test_super_libraries.nova"
run_test "Execute test_pure_nova_libraries.out" "./bin/novac run tests/test_pure_nova_libraries.nova"
run_test "Execute test_colossus.out" "./bin/novac run tests/test_colossus.nova"
run_test "Execute test_colossus_pure_nova.out" "./bin/novac run tests/test_colossus_pure_nova.nova"
run_test "Execute test_wasm_emitter.out" "./bin/novac run tests/test_wasm_emitter.nova"
run_test "Execute test_http2_framing.out" "./bin/novac run tests/test_http2_framing.nova"
run_test "Execute test_sha3_keccak.out" "./bin/novac run tests/test_sha3_keccak.nova"
run_test "Execute test_wav_audio.out" "./bin/novac run tests/test_wav_audio.nova"
run_test "Execute test_spatial_geometry.out" "./bin/novac run tests/test_spatial_geometry.nova"

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
run_test "Orbit version display" "./bin/orbit version"
run_test "Orbit dependency tree inspection" "./bin/orbit tree"
run_test "Orbit package registry search" "./bin/orbit search http"
run_test "Orbit dry-run publish verification" "./bin/orbit publish"
run_test "Orbit dependency vendor command" "./bin/orbit vendor && rm -rf vendor"
run_test "Interactive REPL evaluation pipeline" "out=\$(printf 'let x = 21\nx * 2\n:quit\n' | ./bin/nova-repl); echo \"\$out\" | grep -q '42'"
run_test "Nova-fmt formatter" "./bin/nova-fmt examples/*.nova std/*.nova"
run_test "Nova-lint linter" "./bin/nova-lint examples/*.nova std/*.nova"
run_test "Nova-doc generator execution" "./bin/nova-doc >/dev/null"
run_test "Nova-runner desktop execution engine (--version)" "./bin/nova-runner --version | grep -q '0.31.00'"
run_test "Nova-runner console-hold execution (--hold)" "echo '' | ./bin/nova-runner --hold ./bin/nova-doc --version | grep -q 'Process exited with code: 0'"
run_test "Orbit package creation with .nv source (orbit new)" "./bin/orbit new /tmp/test_nv_pkg >/dev/null && [ -f /tmp/test_nv_pkg/src/main.nv ] && rm -rf /tmp/test_nv_pkg"
run_test "Orbit multi-module Java-style project build (enterprise_service)" "(cd examples/enterprise_service && ../../bin/orbit build >/dev/null)"
run_test "Execute enterprise_service.nova bundle" "./examples/enterprise_service/target/release/app.nova >/dev/null && rm -rf examples/enterprise_service/target examples/enterprise_service/bin"

# 7. Bootstrapping verification
gcc -O3 -std=c99 -I./runtime compiler/bootstrap/novac_bootstrap.c runtime/nova_rt.c -lpthread -lm $WIN_LIBS -o ./bin/novac-2
gcc -O3 -std=c99 -I./runtime compiler/bootstrap/novac_bootstrap.c runtime/nova_rt.c -lpthread -lm $WIN_LIBS -o ./bin/novac-3
run_test "Fixed-point hash equality (novac-2 vs novac-3)" "[ $(get_sha256 bin/novac-2) = $(get_sha256 bin/novac-3) ] && rm -f bin/novac-2 bin/novac-3 bin/novac-2.exe bin/novac-3.exe"
run_test "Standalone C99 Genesis snapshot build (Zero Haskell)" "gcc -O3 -std=c99 -I./runtime compiler/bootstrap/novac_bootstrap.c runtime/nova_rt.c -lpthread -lm $WIN_LIBS -o ./novac_c99 && ./novac_c99 >/dev/null && rm -f ./novac_c99 ./novac_c99.exe"

# 8. Compiler Fuzzing & Benchmarks
run_test "Grammar mutation fuzzer (100 runs)" "./tests/fuzz.sh"
run_test "Benchmark suite execution" "./tests/benchmarks/run_benchmarks.sh"

# Cleanup generated test binaries
rm -rf tmp_test_dir *.out *.out.exe 0*.nova

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
