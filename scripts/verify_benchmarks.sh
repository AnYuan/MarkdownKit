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

run_suite() {
  local name="$1"
  local filter="$2"

  echo
  echo "============================================================"
  echo "[START] $name"
  echo "Command: swift test --filter \"$filter\""
  echo "============================================================"

  if swift test --filter "$filter"; then
    echo "[PASS] $name"
  else
    echo "[FAIL] $name"
    FAILURES+=("$name")
  fi
}

run_suite "Benchmark Full Report" "MarkdownKitBenchmarkTests/testBenchmarkFullReport"
run_suite "Benchmark Node Deep Report" "BenchmarkNodeTypeTests/testDeepBenchmarkFullReport"
run_suite "Benchmark Syntax Tiered" "BenchmarkNodeTypeTests/testPerSyntaxTieredBenchmark"
run_suite "Benchmark Cache" "BenchmarkCacheTests"

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
