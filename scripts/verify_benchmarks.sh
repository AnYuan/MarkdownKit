#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

declare -a FAILURES=()

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required to run scripts/render_benchmark_baseline.py but was not found on PATH." >&2
  exit 1
fi

echo
echo "============================================================"
echo "[START] Benchmark Baseline Freshness"
echo "Command: python3 scripts/render_benchmark_baseline.py --check"
echo "============================================================"

if python3 scripts/render_benchmark_baseline.py --check; then
  echo "[PASS] Benchmark Baseline Freshness"
else
  echo "[FAIL] Benchmark Baseline Freshness"
  echo
  echo "Benchmark verification failed. Failed suites:"
  echo " - Benchmark Baseline Freshness"
  echo
  echo "The baseline JSON is malformed or docs/BENCHMARK_BASELINE.md is missing or stale."
  echo "Fix Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json and/or run:"
  echo "  python3 scripts/render_benchmark_baseline.py"
  echo "before rerunning the timing suites."
  exit 1
fi

echo
echo "============================================================"
echo "[START] Benchmark Release Build"
echo "Command: swift test -c release list"
echo "============================================================"

TEST_LIST_OUTPUT="$(swift test -c release list)"
TEST_LIST_STATUS=$?

if [[ "$TEST_LIST_STATUS" -ne 0 ]]; then
  echo "[FAIL] Benchmark Release Build"
  echo
  echo "Benchmark verification failed. Failed suites:"
  echo " - Benchmark Release Build"
  exit 1
fi

if [[ -z "$TEST_LIST_OUTPUT" ]]; then
  echo "[FAIL] Benchmark Release Build"
  echo
  echo "Benchmark verification failed: Release test discovery returned no tests."
  exit 1
fi

echo "[PASS] Benchmark Release Build"

BENCHMARK_NAMES=(
  "Core Parse"
  "Core Layout"
  "Core Cache"
  "Per-Node Comparison"
  "Width Scaling"
  "Input Size Scaling"
  "Plugin Composition"
  "Concurrent Solve Stress"
  "Syntax Tiered"
  "Cache Micro"
  "Cache Eviction Pressure"
)

BENCHMARK_TEST_IDS=(
  "MarkdownKitTests.MarkdownKitBenchmarkTests/testPhase1_Parse"
  "MarkdownKitTests.MarkdownKitBenchmarkTests/testPhase2_Layout"
  "MarkdownKitTests.MarkdownKitBenchmarkTests/testCacheHitMissRates"
  "MarkdownKitTests.BenchmarkNodeTypeTests/testPerNodeTypeComparison"
  "MarkdownKitTests.BenchmarkNodeTypeTests/testWidthScaling"
  "MarkdownKitTests.BenchmarkNodeTypeTests/testInputSizeScaling"
  "MarkdownKitTests.BenchmarkNodeTypeTests/testPluginCompositionOverhead"
  "MarkdownKitTests.BenchmarkNodeTypeTests/testConcurrentSolveStress"
  "MarkdownKitTests.BenchmarkNodeTypeTests/testPerSyntaxTieredBenchmark"
  "MarkdownKitTests.BenchmarkCacheTests/testCacheGetSetMicro"
  "MarkdownKitTests.BenchmarkCacheTests/testCacheEvictionPressure"
)

if [[ "${#BENCHMARK_NAMES[@]}" -ne "${#BENCHMARK_TEST_IDS[@]}" ]]; then
  echo "Benchmark verification failed: workload names and test identifiers are out of sync." >&2
  exit 1
fi

for index in "${!BENCHMARK_TEST_IDS[@]}"; do
  test_id="${BENCHMARK_TEST_IDS[$index]}"
  match_count="$(printf '%s\n' "$TEST_LIST_OUTPUT" | grep -Fxc "$test_id" || true)"
  if [[ "$match_count" -ne 1 ]]; then
    FAILURES+=("${BENCHMARK_NAMES[$index]} (expected exactly one discovered test named '$test_id', found $match_count)")
  fi
done

if (( ${#FAILURES[@]} > 0 )); then
  echo
  echo "Benchmark verification failed during workload discovery:"
  for suite in "${FAILURES[@]}"; do
    echo " - $suite"
  done
  exit 1
fi

run_suite() {
  local name="$1"
  local test_id="$2"
  local filter

  filter="^${test_id//./\\.}$"

  echo
  echo "============================================================"
  echo "[START] $name"
  echo "Command: swift test -c release --skip-build --filter \"$filter\""
  echo "============================================================"

  if swift test -c release --skip-build --filter "$filter"; then
    echo "[PASS] $name"
  else
    echo "[FAIL] $name"
    FAILURES+=("$name")
  fi
}

# Canonical gates: each workload runs in its own Release-optimized process so
# measurements are not contaminated by other suites running in the same binary.
# testBenchmarkFullReport and testDeepBenchmarkFullReport are intentionally
# excluded — they are composite informational methods that do not own guarded
# assertions.
for index in "${!BENCHMARK_TEST_IDS[@]}"; do
  run_suite "${BENCHMARK_NAMES[$index]}" "${BENCHMARK_TEST_IDS[$index]}"
done

if (( ${#FAILURES[@]} > 0 )); then
  echo
  echo "Benchmark verification failed. Failed suites:"
  for suite in "${FAILURES[@]}"; do
    echo " - $suite"
  done
  exit 1
fi

echo
echo "Benchmark verification passed."
