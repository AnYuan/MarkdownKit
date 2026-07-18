#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WITH_BENCHMARKS=0
FULL_SUITE=0

usage() {
  cat <<'EOF'
Usage: bash scripts/verify_all.sh [--with-benchmarks|-b] [--full|-f]

Runs layered verification.
- always: resolve package graph + release provenance (`scripts/verify_provenance.sh`)
- default: fast regression suites (`scripts/verify_fast.sh`) + both public API baselines
- --with-benchmarks: add heavy benchmark suites (`scripts/verify_benchmarks.sh`)
- --full: provenance + one-shot full validation via `swift test` + both public API baselines
EOF
}

for arg in "$@"; do
  case "$arg" in
    --full|-f)
      FULL_SUITE=1
      ;;
    --with-benchmarks|-b)
      WITH_BENCHMARKS=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      usage
      exit 2
      ;;
  esac
done

run_provenance() {
  echo
  echo "============================================================"
  echo "[START] Provenance"
  echo "Command: bash scripts/verify_provenance.sh"
  echo "============================================================"
  if ! bash scripts/verify_provenance.sh; then
    echo "[FAIL] Provenance"
    exit 1
  fi
  echo "[PASS] Provenance"
}

run_full_suite() {
  echo
  echo "============================================================"
  echo "[START] Full Suite"
  echo "Command: swift test"
  echo "============================================================"
  if swift test; then
    echo "[PASS] Full Suite"
    return
  fi

  echo "[FAIL] Full Suite"
  exit 1
}

run_public_api() {
  local platform="$1"
  local label="$2"
  echo
  echo "============================================================"
  echo "[START] Public API Baseline ($label)"
  echo "Command: bash scripts/verify_public_api.sh --platform $platform --check"
  echo "============================================================"
  if ! bash scripts/verify_public_api.sh --platform "$platform" --check; then
    echo "[FAIL] Public API Baseline ($label)"
    exit 1
  fi
  echo "[PASS] Public API Baseline ($label)"
}

run_provenance

if [[ "$FULL_SUITE" -eq 1 ]]; then
  run_full_suite
else
  echo
  echo "Running fast verification suites..."
  if ! bash scripts/verify_fast.sh; then
    exit 1
  fi

  if [[ "$WITH_BENCHMARKS" -eq 1 ]]; then
    echo
    echo "Running benchmark verification suites..."
    if ! bash scripts/verify_benchmarks.sh; then
      exit 1
    fi
  else
    echo
    echo "[SKIP] Benchmark suites (pass --with-benchmarks to include them)."
  fi
fi

run_public_api "macos" "macOS"
run_public_api "ios-simulator" "iOS Simulator"

echo
echo "Verification passed: selected suites completed successfully."
