#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILTER='^MarkdownKitTests\.SnapshotTests/'
SNAPSHOT_REL='Tests/MarkdownKitTests/__Snapshots__/SnapshotTests'
SNAPSHOT_DIR="$ROOT_DIR/$SNAPSHOT_REL"
MODE="${1:-}"

usage() {
  echo "Usage: bash scripts/verify_snapshots.sh --visual|--determinism"
}

if [[ "$#" -ne 1 ]]; then
  usage
  exit 2
fi

case "$MODE" in
  --visual|--determinism)
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ ! -d "$SNAPSHOT_DIR" ]]; then
  echo "ERROR: Snapshot directory does not exist: $SNAPSHOT_REL" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required to preserve and validate snapshot baselines." >&2
  exit 1
fi

if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]]; then
  echo "ERROR: Snapshot verification must run inside a git worktree." >&2
  exit 1
fi

TEMP_ROOT="$ROOT_DIR/.build/verify-snapshots.$$"
if [[ -e "$TEMP_ROOT" ]]; then
  echo "ERROR: Temporary workspace already exists: $TEMP_ROOT" >&2
  exit 1
fi
if ! mkdir -p "$ROOT_DIR/.build" || ! mkdir "$TEMP_ROOT"; then
  echo "ERROR: Could not create temporary workspace: $TEMP_ROOT" >&2
  exit 1
fi

BACKUP_DIR="$TEMP_ROOT/original-snapshots"
if ! PRE_STATUS="$(git status --porcelain -- "$SNAPSHOT_REL")"; then
  echo "ERROR: Could not read the snapshot directory git status." >&2
  rm -rf "$TEMP_ROOT"
  exit 1
fi
if ! cp -R "$SNAPSHOT_DIR" "$BACKUP_DIR"; then
  echo "ERROR: Could not back up the snapshot directory." >&2
  rm -rf "$TEMP_ROOT"
  exit 1
fi

cleanup() {
  local status=$?
  local post_status
  local restored=0

  trap - EXIT INT TERM HUP

  if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "ERROR: Snapshot backup is missing; cannot restore $SNAPSHOT_REL." >&2
    status=1
  elif ! rm -rf "$SNAPSHOT_DIR"; then
    echo "ERROR: Could not remove the temporary snapshot directory." >&2
    status=1
  elif ! mv "$BACKUP_DIR" "$SNAPSHOT_DIR"; then
    echo "ERROR: Could not restore the snapshot directory from $BACKUP_DIR." >&2
    status=1
  else
    restored=1
  fi

  if [[ "$restored" -eq 1 ]]; then
    if ! post_status="$(git status --porcelain -- "$SNAPSHOT_REL")"; then
      echo "ERROR: Could not verify the restored snapshot directory git status." >&2
      status=1
    elif [[ "$post_status" != "$PRE_STATUS" ]]; then
      echo "ERROR: Snapshot directory git status was not restored." >&2
      echo "Before:" >&2
      printf '%s\n' "$PRE_STATUS" >&2
      echo "After:" >&2
      printf '%s\n' "$post_status" >&2
      status=1
    fi

    rm -rf "$TEMP_ROOT"
  else
    echo "ERROR: Recovery data has been preserved at $TEMP_ROOT." >&2
  fi

  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

LIST_LOG="$TEMP_ROOT/test-list.log"
if ! swift test list > "$LIST_LOG"; then
  echo "ERROR: 'swift test list' failed." >&2
  exit 1
fi

if [[ ! -s "$LIST_LOG" ]]; then
  echo "ERROR: 'swift test list' returned no output." >&2
  exit 1
fi

MALFORMED_LINES="$(grep -nEv '^MarkdownKitTests\.[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*$' "$LIST_LOG" || true)"
if [[ -n "$MALFORMED_LINES" ]]; then
  echo "ERROR: 'swift test list' returned malformed output:" >&2
  printf '%s\n' "$MALFORMED_LINES" >&2
  exit 1
fi

TEST_LINES="$TEMP_ROOT/snapshot-tests.log"
grep -E "$FILTER" "$LIST_LOG" > "$TEST_LINES" || true
EXPECTED_COUNT="$(wc -l < "$TEST_LINES" | tr -d '[:space:]')"

case "$EXPECTED_COUNT" in
  ''|*[!0-9]*)
    echo "ERROR: Could not determine the SnapshotTests count." >&2
    exit 1
    ;;
  0)
    echo "ERROR: Exact filter '$FILTER' discovered zero tests." >&2
    exit 1
    ;;
esac

echo "Discovered $EXPECTED_COUNT test(s) with exact filter: $FILTER"

png_count() {
  find "$SNAPSHOT_DIR" -maxdepth 1 -type f -name '*.png' -print | wc -l | tr -d '[:space:]'
}

require_one_png_per_test() {
  local line
  local test_name
  local count
  local total

  while IFS= read -r line; do
    test_name="${line##*/}"
    count="$(find "$SNAPSHOT_DIR" -maxdepth 1 -type f -name "$test_name.*.png" -print | wc -l | tr -d '[:space:]')"
    if [[ "$count" -ne 1 ]]; then
      echo "ERROR: Expected exactly one PNG for $line, found $count." >&2
      return 1
    fi
  done < "$TEST_LINES"

  total="$(png_count)"
  if [[ "$total" -ne "$EXPECTED_COUNT" ]]; then
    echo "ERROR: Expected exactly $EXPECTED_COUNT PNG(s), found $total." >&2
    return 1
  fi
}

require_one_tracked_png_per_test() {
  local line
  local test_name
  local count
  local total

  while IFS= read -r line; do
    test_name="${line##*/}"
    count="$(git ls-files -- "$SNAPSHOT_REL/$test_name.*.png" | wc -l | tr -d '[:space:]')"
    if [[ "$count" -ne 1 ]]; then
      echo "ERROR: Expected exactly one git-tracked PNG for $line, found $count." >&2
      return 1
    fi
  done < "$TEST_LINES"

  total="$(git ls-files -- "$SNAPSHOT_REL/*.png" | wc -l | tr -d '[:space:]')"
  if [[ "$total" -ne "$EXPECTED_COUNT" ]]; then
    echo "ERROR: Expected exactly $EXPECTED_COUNT git-tracked PNG(s), found $total." >&2
    return 1
  fi
}

EXECUTED_COUNT=
FAILURE_COUNT=
parse_test_summary() {
  local log_file="$1"
  local summary

  summary="$(grep -E 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$log_file" | tail -n 1 || true)"
  if [[ -z "$summary" ]]; then
    echo "ERROR: Test output has no XCTest execution summary." >&2
    return 1
  fi

  EXECUTED_COUNT="$(printf '%s\n' "$summary" | sed -E 's/.*Executed ([0-9]+) tests?, with ([0-9]+) failures?.*/\1/')"
  FAILURE_COUNT="$(printf '%s\n' "$summary" | sed -E 's/.*Executed ([0-9]+) tests?, with ([0-9]+) failures?.*/\2/')"

  case "$EXECUTED_COUNT:$FAILURE_COUNT" in
    *[!0-9:]*|:*|*:)
      echo "ERROR: Malformed XCTest execution summary: $summary" >&2
      return 1
      ;;
  esac
}

run_suite() {
  local label="$1"
  local log_file="$2"

  echo
  echo "[$label] swift test --filter '$FILTER'"
  swift test --filter "$FILTER" 2>&1 | tee "$log_file"
  RUN_STATUS=${PIPESTATUS[0]}
}

if [[ "$MODE" == "--visual" ]]; then
  if ! require_one_tracked_png_per_test; then
    exit 1
  fi
  if ! require_one_png_per_test; then
    exit 1
  fi
  run_suite "VISUAL" "$TEMP_ROOT/visual.log"
  if ! parse_test_summary "$TEMP_ROOT/visual.log"; then
    exit 1
  fi

  if [[ "$EXECUTED_COUNT" -eq 0 || "$EXECUTED_COUNT" -ne "$EXPECTED_COUNT" ]]; then
    echo "ERROR: Visual pass executed $EXECUTED_COUNT test(s); expected $EXPECTED_COUNT." >&2
    exit 1
  fi
  if [[ "$FAILURE_COUNT" -ne 0 || "$RUN_STATUS" -ne 0 ]]; then
    echo "ERROR: Visual pass reported $FAILURE_COUNT failure(s), exit status $RUN_STATUS." >&2
    exit 1
  fi

  echo "Visual verification passed: $EXECUTED_COUNT test(s), 0 failures."
  exit 0
fi

if ! rm -rf "$SNAPSHOT_DIR" || ! mkdir "$SNAPSHOT_DIR"; then
  echo "ERROR: Could not prepare an empty snapshot directory for recording." >&2
  exit 1
fi

run_suite "DETERMINISM RECORD" "$TEMP_ROOT/record.log"
RECORD_STATUS="$RUN_STATUS"
if ! parse_test_summary "$TEMP_ROOT/record.log"; then
  exit 1
fi
RECORD_EXECUTED="$EXECUTED_COUNT"
RECORD_FAILURES="$FAILURE_COUNT"
MISSING_COUNT="$(grep -c 'No reference was found on disk' "$TEMP_ROOT/record.log" || true)"
UNEXPECTED_FAILURES="$(grep -E 'error: .* : failed - ' "$TEMP_ROOT/record.log" | grep -v 'No reference was found on disk' || true)"
GENERATED_COUNT="$(png_count)"

if [[ "$RECORD_STATUS" -eq 0 ]]; then
  echo "ERROR: Record pass unexpectedly succeeded; missing references must fail while recording." >&2
  exit 1
fi
if [[ "$RECORD_EXECUTED" -eq 0 || "$RECORD_EXECUTED" -ne "$EXPECTED_COUNT" ]]; then
  echo "ERROR: Record pass executed $RECORD_EXECUTED test(s); expected $EXPECTED_COUNT." >&2
  exit 1
fi
if [[ "$RECORD_FAILURES" -ne "$EXPECTED_COUNT" || "$MISSING_COUNT" -ne "$EXPECTED_COUNT" ]]; then
  echo "ERROR: Record pass had $RECORD_FAILURES failure(s) and $MISSING_COUNT missing-reference failure(s); expected $EXPECTED_COUNT of each." >&2
  exit 1
fi
if [[ -n "$UNEXPECTED_FAILURES" ]]; then
  echo "ERROR: Record pass contained unexpected failures:" >&2
  printf '%s\n' "$UNEXPECTED_FAILURES" >&2
  exit 1
fi
if [[ "$GENERATED_COUNT" -ne "$EXPECTED_COUNT" ]]; then
  echo "ERROR: Record pass generated $GENERATED_COUNT PNG(s); expected $EXPECTED_COUNT." >&2
  exit 1
fi
if ! require_one_png_per_test; then
  exit 1
fi

run_suite "DETERMINISM VERIFY" "$TEMP_ROOT/verify.log"
if ! parse_test_summary "$TEMP_ROOT/verify.log"; then
  exit 1
fi

if [[ "$EXECUTED_COUNT" -eq 0 || "$EXECUTED_COUNT" -ne "$EXPECTED_COUNT" ]]; then
  echo "ERROR: Verify pass executed $EXECUTED_COUNT test(s); expected $EXPECTED_COUNT." >&2
  exit 1
fi
if [[ "$FAILURE_COUNT" -ne 0 || "$RUN_STATUS" -ne 0 ]]; then
  echo "ERROR: Verify pass reported $FAILURE_COUNT failure(s), exit status $RUN_STATUS." >&2
  exit 1
fi

echo "Determinism verification passed: record $RECORD_EXECUTED/$EXPECTED_COUNT expected failures and verify $EXECUTED_COUNT test(s), 0 failures."
