#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

declare -a FAILURES=()

run_suite() {
  local name="$1"
  local filter="$2"
  local output_file
  local status

  echo
  echo "============================================================"
  echo "[START] $name"
  echo "Command: swift test --filter \"$filter\""
  echo "============================================================"

  if ! output_file="$(mktemp "${TMPDIR:-/tmp}/markdownkit-verify-fast.XXXXXX")"; then
    echo "[FAIL] $name (could not create output log)"
    FAILURES+=("$name")
    return
  fi

  swift test --filter "$filter" 2>&1 | tee "$output_file"
  status=$?

  # Guard against a filter that (due to a discovery or quoting bug) matches
  # zero tests: `swift test --filter` exits 0 in that case, which would
  # otherwise look like a passing, success-shaped no-op.
  if [[ "$status" -eq 0 ]] && grep -q "Executed 0 tests" "$output_file"; then
    echo "[FAIL] $name (matched zero tests - treating as a failure, not a no-op pass)"
    status=1
  fi
  rm -f "$output_file"

  if [[ "$status" -eq 0 ]]; then
    echo "[PASS] $name"
  else
    echo "[FAIL] $name"
    FAILURES+=("$name")
  fi
}

# ---------------------------------------------------------------------------
# Discover every XCTest suite in MarkdownKitTests via `swift test list` and
# build a correctness gate from it, instead of a hand-maintained allow-list.
# Any newly added ordinary test class is picked up automatically. Two
# categories are carved out of the discovered set:
#   - Benchmark suites (heavy, timing-sensitive) stay owned by
#     scripts/verify_benchmarks.sh.
#   - The true environment-sensitive snapshot suites (SnapshotTests,
#     iOSSnapshotTests) are excluded entirely from this gate in every
#     environment (local and CI). They are owned exclusively by
#     scripts/verify_snapshots.sh (--visual / --determinism), never by this
#     script. DiagramSnapshotTests is a deterministic correctness suite and
#     is deliberately NOT excluded here.
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "[DISCOVER] Enumerating tests via 'swift test list'"
echo "============================================================"

TEST_LIST_OUTPUT="$(swift test list)"
TEST_LIST_STATUS=$?

if [[ "$TEST_LIST_STATUS" -ne 0 ]]; then
  echo "ERROR: 'swift test list' failed with exit code $TEST_LIST_STATUS." >&2
  exit 1
fi

if [[ -z "$TEST_LIST_OUTPUT" ]]; then
  echo "ERROR: 'swift test list' returned no output. Refusing to run an empty correctness gate." >&2
  exit 1
fi

TOTAL_LINES=$(printf '%s\n' "$TEST_LIST_OUTPUT" | grep -c .)
MATCHED_LINES=$(printf '%s\n' "$TEST_LIST_OUTPUT" | grep -c -E '^MarkdownKitTests\.[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*$')

if [[ "$MATCHED_LINES" -ne "$TOTAL_LINES" ]]; then
  echo "ERROR: 'swift test list' produced $((TOTAL_LINES - MATCHED_LINES)) line(s) that do not match the expected 'MarkdownKitTests.Class/testMethod' format:" >&2
  printf '%s\n' "$TEST_LIST_OUTPUT" | grep -v -E '^MarkdownKitTests\.[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*$' >&2
  exit 1
fi

ALL_SUITES=()
while IFS= read -r suite; do
  [[ -n "$suite" ]] && ALL_SUITES+=("$suite")
done < <(printf '%s\n' "$TEST_LIST_OUTPUT" | sed -E 's/^MarkdownKitTests\.([A-Za-z_][A-Za-z0-9_]*)\/.*/\1/' | sort -u)

if (( ${#ALL_SUITES[@]} == 0 )); then
  echo "ERROR: No test suites discovered. Refusing to run an empty correctness gate." >&2
  exit 1
fi

BENCHMARK_SUITES=()
TRUE_SNAPSHOT_SUITES=()
CORRECTNESS_SUITES=()

for suite in "${ALL_SUITES[@]}"; do
  case "$suite" in
    *Benchmark*)
      BENCHMARK_SUITES+=("$suite")
      ;;
    SnapshotTests|iOSSnapshotTests)
      TRUE_SNAPSHOT_SUITES+=("$suite")
      ;;
    *)
      CORRECTNESS_SUITES+=("$suite")
      ;;
  esac
done

if (( ${#CORRECTNESS_SUITES[@]} == 0 )); then
  echo "ERROR: Discovery excluded every suite (benchmark/snapshot filters too broad?). Refusing to run an empty correctness gate." >&2
  exit 1
fi

join_with_pipe() {
  local IFS='|'
  echo "$*"
}

echo "Discovered ${#ALL_SUITES[@]} suite(s) total."
echo "Benchmark suites excluded (owned by scripts/verify_benchmarks.sh): $(join_with_pipe "${BENCHMARK_SUITES[@]:-}")"
echo "True snapshot suites excluded (owned by scripts/verify_snapshots.sh, not run here): $(join_with_pipe "${TRUE_SNAPSHOT_SUITES[@]:-}")"
echo "Correctness suites included (${#CORRECTNESS_SUITES[@]}): $(join_with_pipe "${CORRECTNESS_SUITES[@]}")"

CORRECTNESS_FILTER="^MarkdownKitTests\\.($(join_with_pipe "${CORRECTNESS_SUITES[@]}"))/"

run_suite "Correctness Gate (discovery-driven, all non-benchmark/non-snapshot suites)" "$CORRECTNESS_FILTER"

echo
echo "============================================================"
echo "[INFO] Snapshot Contracts"
echo "This script is correctness-only in every environment (local and CI)."
echo "SnapshotTests and iOSSnapshotTests are never run here."
echo "They are owned exclusively by scripts/verify_snapshots.sh:"
echo "  bash scripts/verify_snapshots.sh --visual"
echo "  bash scripts/verify_snapshots.sh --determinism"
echo "============================================================"

if (( ${#FAILURES[@]} > 0 )); then
  echo
  echo "Fast verification failed. Failed suites:"
  for suite in "${FAILURES[@]}"; do
    echo " - $suite"
  done
  exit 1
fi

echo

echo "Fast verification passed."
