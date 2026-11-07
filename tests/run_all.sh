#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NOVA_RUNTIME="$ROOT_DIR/runtime"
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
if [ ! -f bin/orbit ] && [ -f tests/tools/orbit/main.nv ]; then ./bin/novac build tests/tools/orbit/main.nv >/dev/null 2>&1 || true; if [ -f main.out ]; then mv main.out bin/orbit; fi; if [ -f main.out.exe ]; then mv main.out.exe bin/orbit.exe; cp -f bin/orbit.exe bin/orbit 2>/dev/null || true; fi; fi
if [ ! -f bin/nova-doc ] && [ -f tests/tools/docgen/nova_doc ]; then cp tests/tools/docgen/nova_doc bin/nova-doc; fi
if [ ! -f bin/nova-doc ] && [ -f tests/tools/docgen/main.nv ]; then ./bin/novac build tests/tools/docgen/main.nv >/dev/null 2>&1 || true; if [ -f main.out ]; then mv main.out bin/nova-doc; fi; if [ -f main.out.exe ]; then mv main.out.exe bin/nova-doc.exe; cp -f bin/nova-doc.exe bin/nova-doc 2>/dev/null || true; fi; fi
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
run_test "Check 01_hello.nv" "./bin/novac check examples/01_hello.nv"
run_test "Check 02_refinements_z3.nv" "./bin/novac check examples/02_refinements_z3.nv"
run_test "Check 03_perceus_tree.nv" "./bin/novac check examples/03_perceus_tree.nv"
run_test "Check 04_concurrency_channels.nv" "./bin/novac check examples/04_concurrency_channels.nv"
run_test "Check 06_snake_game.nv" "./bin/novac check examples/06_snake_game.nv"
run_test "Check 07_network_http_server.nv" "./bin/novac check examples/07_network_http_server.nv"
run_test "Check 08_traits_and_baremetal.nv" "./bin/novac check examples/08_traits_and_baremetal.nv"
run_test "Check 09_std_industrial.nv" "./bin/novac check examples/09_std_industrial.nv"
run_test "Check 10_btree_database.nv" "./bin/novac check examples/10_btree_database.nv"
run_test "Check 11_bloom_filter_cache.nv" "./bin/novac check examples/11_bloom_filter_cache.nv"
run_test "Check 12_matrix_neural_network.nv" "./bin/novac check examples/12_matrix_neural_network.nv"
run_test "Check 13_compression_pipeline.nv" "./bin/novac check examples/13_compression_pipeline.nv"
run_test "Check 14_priority_task_scheduler.nv" "./bin/novac check examples/14_priority_task_scheduler.nv"
run_test "Check 15_cryptographic_vault.nv" "./bin/novac check examples/15_cryptographic_vault.nv"
run_test "Check 16_toml_config_engine.nv" "./bin/novac check examples/16_toml_config_engine.nv"
run_test "Check 17_unicode_scanner.nv" "./bin/novac check examples/17_unicode_scanner.nv"
run_test "Check 18_3d_graphics_pipeline.nv" "./bin/novac check examples/18_3d_graphics_pipeline.nv"
run_test "Check 19_bmp_image_generator.nv" "./bin/novac check examples/19_bmp_image_generator.nv"
run_test "Check 20_sha512_crypto_hasher.nv" "./bin/novac check examples/20_sha512_crypto_hasher.nv"
run_test "Check 21_wasm_emitter.nv" "./bin/novac check examples/21_wasm_emitter.nv"
run_test "Check 22_http2_frame_pipeline.nv" "./bin/novac check examples/22_http2_frame_pipeline.nv"
run_test "Check 23_sha3_keccak.nv" "./bin/novac check examples/23_sha3_keccak.nv"
run_test "Check 24_wav_audio_synth.nv" "./bin/novac check examples/24_wav_audio_synth.nv"
run_test "Check 25_spatial_kdtree.nv" "./bin/novac check examples/25_spatial_kdtree.nv"
run_test "Check compiler/types.nv" "./bin/novac check compiler/types.nv"
run_test "Check compiler/lexer.nv" "./bin/novac check compiler/lexer.nv"
run_test "Check compiler/parser.nv" "./bin/novac check compiler/parser.nv"
run_test "Check compiler/checker.nv" "./bin/novac check compiler/checker.nv"
run_test "Check compiler/codegen_c.nv" "./bin/novac check compiler/codegen_c.nv"
run_test "Check compiler/codegen_llvm.nv" "./bin/novac check compiler/codegen_llvm.nv"
run_test "Check compiler/codegen_cranelift.nv" "./bin/novac check compiler/codegen_cranelift.nv"
run_test "Check compiler/codegen_wasm.nv" "./bin/novac check compiler/codegen_wasm.nv"
run_test "Check compiler/x86_tables.nv" "./bin/novac check compiler/x86_tables.nv"
run_test "Check compiler/arm64_tables.nv" "./bin/novac check compiler/arm64_tables.nv"
run_test "Check compiler/riscv_tables.nv" "./bin/novac check compiler/riscv_tables.nv"
run_test "Check compiler/wasm_tables.nv" "./bin/novac check compiler/wasm_tables.nv"
run_test "Check compiler/optimizer.nv" "./bin/novac check compiler/optimizer.nv"
run_test "Check compiler/main.nv" "./bin/novac check compiler/main.nv"

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
run_test "Check std/vec.nv" "./bin/novac check std/vec.nv"
run_test "Check std/map.nv" "./bin/novac check std/map.nv"
run_test "Check std/string.nv" "./bin/novac check std/string.nv"
run_test "Check std/io.nv" "./bin/novac check std/io.nv"
run_test "Check std/sync.nv" "./bin/novac check std/sync.nv"
run_test "Check std/fs.nv" "./bin/novac check std/fs.nv"
run_test "Check std/net.nv" "./bin/novac check std/net.nv"
run_test "Check std/json.nv" "./bin/novac check std/json.nv"
run_test "Check std/os.nv" "./bin/novac check std/os.nv"
run_test "Check std/math.nv" "./bin/novac check std/math.nv"
run_test "Check std/time.nv" "./bin/novac check std/time.nv"
run_test "Check std/crypto.nv" "./bin/novac check std/crypto.nv"
run_test "Check std/http.nv" "./bin/novac check std/http.nv"
run_test "Check std/collections.nv" "./bin/novac check std/collections.nv"
run_test "Check std/collections_adv.nv" "./bin/novac check std/collections_adv.nv"
run_test "Check std/crypto_adv.nv" "./bin/novac check std/crypto_adv.nv"
run_test "Check std/storage.nv" "./bin/novac check std/storage.nv"
run_test "Check std/db.nv" "./bin/novac check std/db.nv"
run_test "Check std/encoding.nv" "./bin/novac check std/encoding.nv"
run_test "Check std/bloom.nv" "./bin/novac check std/bloom.nv"
run_test "Check std/lru.nv" "./bin/novac check std/lru.nv"
run_test "Check std/queue.nv" "./bin/novac check std/queue.nv"
run_test "Check std/matrix.nv" "./bin/novac check std/matrix.nv"
run_test "Check std/hash.nv" "./bin/novac check std/hash.nv"
run_test "Check std/bigint.nv" "./bin/novac check std/bigint.nv"
run_test "Check std/uuid.nv" "./bin/novac check std/uuid.nv"
run_test "Check std/ansi.nv" "./bin/novac check std/ansi.nv"
run_test "Check std/uri.nv" "./bin/novac check std/uri.nv"
run_test "Check std/tar.nv" "./bin/novac check std/tar.nv"
run_test "Check std/compress.nv" "./bin/novac check std/compress.nv"
run_test "Check std/btree.nv" "./bin/novac check std/btree.nv"
run_test "Check std/regex.nv" "./bin/novac check std/regex.nv"
run_test "Check std/async.nv" "./bin/novac check std/async.nv"
run_test "Check std/aes.nv" "./bin/novac check std/aes.nv"
run_test "Check std/sha256.nv" "./bin/novac check std/sha256.nv"
run_test "Check std/chacha20.nv" "./bin/novac check std/chacha20.nv"
run_test "Check std/toml.nv" "./bin/novac check std/toml.nv"
run_test "Check std/csv.nv" "./bin/novac check std/csv.nv"
run_test "Check std/unicode.nv" "./bin/novac check std/unicode.nv"
run_test "Check std/math3d.nv" "./bin/novac check std/math3d.nv"
run_test "Check std/crypto_suite.nv" "./bin/novac check std/crypto_suite.nv"
run_test "Check std/image_bmp.nv" "./bin/novac check std/image_bmp.nv"
run_test "Check std/json_full.nv" "./bin/novac check std/json_full.nv"
run_test "Check std/xml.nv" "./bin/novac check std/xml.nv"
run_test "Check std/http2.nv" "./bin/novac check std/http2.nv"
run_test "Check std/dns.nv" "./bin/novac check std/dns.nv"
run_test "Check std/geometry.nv" "./bin/novac check std/geometry.nv"
run_test "Check std/physics2d.nv" "./bin/novac check std/physics2d.nv"
run_test "Check std/crypto_sha3.nv" "./bin/novac check std/crypto_sha3.nv"
run_test "Check std/sound_wav.nv" "./bin/novac check std/sound_wav.nv"
run_test "Check std/runtime/sys_linux.nv" "./bin/novac check std/runtime/sys_linux.nv"
run_test "Check std/runtime/perceus_alloc.nv" "./bin/novac check std/runtime/perceus_alloc.nv"
run_test "Check std/runtime/sys_windows.nv" "./bin/novac check std/runtime/sys_windows.nv"
run_test "Check compiler/backend/x86_64_enc.nv" "./bin/novac check compiler/backend/x86_64_enc.nv"
run_test "Check compiler/backend/elf64.nv" "./bin/novac check compiler/backend/elf64.nv"
run_test "Check compiler/backend/pe.nv" "./bin/novac check compiler/backend/pe.nv"
run_test "Check std/async_runtime.nv" "./bin/novac check std/async_runtime.nv"
run_test "Check std/colossus_web.nv" "./bin/novac check std/colossus_web.nv"
run_test "Check std/titan_db.nv" "./bin/novac check std/titan_db.nv"
run_test "Check std/aether_gfx.nv" "./bin/novac check std/aether_gfx.nv"
run_test "Check std/ml_tensor.nv" "./bin/novac check std/ml_tensor.nv"
run_test "Check std/crypto_postquantum.nv" "./bin/novac check std/crypto_postquantum.nv"
run_test "Check std/distributed_cluster.nv" "./bin/novac check std/distributed_cluster.nv"
run_test "Check std/tls13.nv" "./bin/novac check std/tls13.nv"
run_test "Check std/grpc_pure.nv" "./bin/novac check std/grpc_pure.nv"
run_test "Check std/columnar_store.nv" "./bin/novac check std/columnar_store.nv"
run_test "Check std/sql_query_engine.nv" "./bin/novac check std/sql_query_engine.nv"
run_test "Check std/linear_algebra.nv" "./bin/novac check std/linear_algebra.nv"
run_test "Check std/lockfree_queue.nv" "./bin/novac check std/lockfree_queue.nv"
run_test "Check std/bytecode_vm.nv" "./bin/novac check std/bytecode_vm.nv"

# 3. Negative safety tests (Z3 SMT proof rejection)
run_rejection_test "Reject division by unproven zero (05_bad_division.nv)" "./bin/novac check examples/05_bad_division.nv"

# 4. Native code execution
run_test "Execute 01_hello.out" "./bin/novac run examples/01_hello.nv"
run_test "Execute 02_refinements_z3.out" "./bin/novac run examples/02_refinements_z3.nv"
run_test "Execute 03_perceus_tree.out" "./bin/novac run examples/03_perceus_tree.nv"
run_test "Execute 04_concurrency_channels.out" "./bin/novac run examples/04_concurrency_channels.nv"
run_test "Execute 08_traits_and_baremetal.out" "./bin/novac run examples/08_traits_and_baremetal.nv"
run_test "Execute 09_std_industrial.out" "./bin/novac run examples/09_std_industrial.nv"
run_test "Execute 10_btree_database.out" "./bin/novac run examples/10_btree_database.nv"
run_test "Execute 11_bloom_filter_cache.out" "./bin/novac run examples/11_bloom_filter_cache.nv"
run_test "Execute 12_matrix_neural_network.out" "./bin/novac run examples/12_matrix_neural_network.nv"
run_test "Execute 13_compression_pipeline.out" "./bin/novac run examples/13_compression_pipeline.nv"
run_test "Execute 14_priority_task_scheduler.out" "./bin/novac run examples/14_priority_task_scheduler.nv"
run_test "Execute 15_cryptographic_vault.out" "./bin/novac run examples/15_cryptographic_vault.nv"
run_test "Execute 16_toml_config_engine.out" "./bin/novac run examples/16_toml_config_engine.nv"
run_test "Execute 17_unicode_scanner.out" "./bin/novac run examples/17_unicode_scanner.nv"
run_test "Execute 18_3d_graphics_pipeline.out" "./bin/novac run examples/18_3d_graphics_pipeline.nv"
run_test "Execute 19_bmp_image_generator.out" "./bin/novac run examples/19_bmp_image_generator.nv"
run_test "Execute 20_sha512_crypto_hasher.out" "./bin/novac run examples/20_sha512_crypto_hasher.nv"
run_test "Execute 21_wasm_emitter.out" "./bin/novac run examples/21_wasm_emitter.nv"
run_test "Execute 22_http2_frame_pipeline.out" "./bin/novac run examples/22_http2_frame_pipeline.nv"
run_test "Execute 23_sha3_keccak.out" "./bin/novac run examples/23_sha3_keccak.nv"
run_test "Execute 24_wav_audio_synth.out" "./bin/novac run examples/24_wav_audio_synth.nv"
run_test "Execute 25_spatial_kdtree.out" "./bin/novac run examples/25_spatial_kdtree.nv"
run_test "Execute test_bloom_filter.out" "./bin/novac run tests/test_bloom_filter.nv"
run_test "Execute test_btree_index.out" "./bin/novac run tests/test_btree_index.nv"
run_test "Execute test_matrix_algebra.out" "./bin/novac run tests/test_matrix_algebra.nv"
run_test "Execute test_lru_cache.out" "./bin/novac run tests/test_lru_cache.nv"
run_test "Execute test_cryptographic_suite.out" "./bin/novac run tests/test_cryptographic_suite.nv"
run_test "Execute test_os_primitives.out" "./bin/novac run tests/test_os_primitives.nv"
run_test "Execute test_super_libraries.out" "./bin/novac run tests/test_super_libraries.nv"
run_test "Execute test_pure_nova_libraries.out" "./bin/novac run tests/test_pure_nova_libraries.nv"
run_test "Execute test_colossus.out" "./bin/novac run tests/test_colossus.nv"
run_test "Execute test_colossus_pure_nova.out" "./bin/novac run tests/test_colossus_pure_nova.nv"
run_test "Execute test_wasm_emitter.out" "./bin/novac run tests/test_wasm_emitter.nv"
run_test "Execute test_http2_framing.out" "./bin/novac run tests/test_http2_framing.nv"
run_test "Execute test_sha3_keccak.out" "./bin/novac run tests/test_sha3_keccak.nv"
run_test "Execute test_wav_audio.out" "./bin/novac run tests/test_wav_audio.nv"
run_test "Execute test_spatial_geometry.out" "./bin/novac run tests/test_spatial_geometry.nv"
run_test "Execute test_million_scale_ecosystem.out" "./bin/novac run tests/test_million_scale_ecosystem.nv"

# 5. Intermediate Representations & Codegen
run_test "Dump HIR (--dump-hir)" "./bin/novac --dump-hir examples/01_hello.nv"
run_test "Dump MIR (--dump-mir)" "./bin/novac --dump-mir examples/01_hello.nv"
run_test "Emit LLVM IR (--emit-llvm)" "./bin/novac --emit-llvm examples/01_hello.nv"
run_test "Emit C99 (--emit-c)" "./bin/novac --emit-c examples/01_hello.nv"

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
run_test "Nova-fmt formatter" "./bin/nova-fmt examples/*.nv std/*.nv"
run_test "Nova-lint linter" "./bin/nova-lint examples/*.nv std/*.nv"
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
rm -rf tmp_test_dir *.out *.out.exe 0*.nova 0*.nv

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
