#!/usr/bin/env bash
#
# Supported iOS Simulator correctness lane for the SwiftPM package.
#
# This script synthesizes a package-only xcodebuild workspace containing
# symlinks to Package.swift, Package.resolved, Sources, and Tests. xcodebuild
# derives the `MarkdownKit-Package` scheme directly from SwiftPM metadata;
# source-tree project and workspace artifacts do not participate.
#
# Suite selection is done by statically scanning Tests/MarkdownKitTests for
# `class X: XCTestCase` declarations rather than via `swift test list`,
# because `swift test list` only enumerates suites buildable for the host
# (macOS) platform and silently omits iOS-only suites (e.g. iOSSnapshotTests,
# iOSAccessibilityTests) that are guarded by `#if canImport(UIKit)`. Scanning
# source text sees every suite regardless of platform guards.
#
# Diagnosability/determinism hardening:
#   - Per-test XCTest timeouts (`-test-timeouts-enabled`) are enabled so a
#     hung test fails with its own name instead of the whole job timing out.
#   - DerivedData is pinned under the repo-local, gitignored build/
#     directory rather than Xcode's global per-user default, so a run is
#     reproducible and `rm -rf build` fully cleans it up.
#   - The log is scanned after a nominal test pass for private system-font
#     fallback diagnostics (e.g. ".SFNS"/".SFUI" round-tripping into a
#     "CoreText note" that silently substitutes Times New Roman), which
#     xcodebuild does not treat as a test failure on its own.
#   - XCTest process restart/crash diagnostics (for example, "Restarting after
#     unexpected exit, crash, or test timeout; summary will include totals
#     from previous launches.") are treated as hard failures even if xcodebuild
#     retries and exits successfully.
#   - This lane assumes a macOS runner with jq preinstalled (see the tool
#     check below); it is required, not optional, and fails with a clear
#     message if missing.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="MarkdownKit-Package"
TEST_TARGET="MarkdownKitTests"
WORKSPACE_DIR="$ROOT_DIR/build/ios-package-workspace"
BUILD_LOG_DIR="$ROOT_DIR/build"
LOG_FILE="$BUILD_LOG_DIR/ios-verify-xcodebuild.log"
SCHEME_LIST_STDERR_FILE="$BUILD_LOG_DIR/ios-scheme-list-stderr.log"
TEST_ENUMERATION_FILE="$BUILD_LOG_DIR/ios-test-enumeration.json"
TEST_ENUMERATION_LOG_FILE="$BUILD_LOG_DIR/ios-test-enumeration.log"
# Keep DerivedData under the repo-local, gitignored build/ directory (see
# .gitignore's `build/` entry) instead of Xcode's global per-user
# ~/Library/Developer/Xcode/DerivedData default, so a run is reproducible
# and fully cleaned up by deleting build/.
DERIVED_DATA_DIR="$ROOT_DIR/build/DerivedData"

# This lane assumes a macOS runner with Xcode command line tools (xcodebuild,
# xcrun) and jq preinstalled, matching GitHub Actions' macOS images. jq is
# required (not optional) to parse `xcodebuild -list -json` and
# `simctl list devices -j` output; fail fast and loudly rather than falling
# back to fragile text parsing if any tool is missing.
for tool in xcodebuild xcrun jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' was not found on PATH." >&2
    echo "This script assumes a macOS runner with Xcode command line tools and jq preinstalled (e.g. GitHub Actions' macos-* images). Install '$tool' or run on such a runner." >&2
    exit 1
  fi
done

echo "============================================================"
echo "[SETUP] Creating package-only xcodebuild workspace"
echo "============================================================"

rm -rf "$WORKSPACE_DIR" "$DERIVED_DATA_DIR"
mkdir -p "$WORKSPACE_DIR" "$DERIVED_DATA_DIR"

# Symlink only SwiftPM package inputs so xcodebuild synthesizes the
# `MarkdownKit-Package` scheme without source-tree project or workspace
# participation.
ln -s "$ROOT_DIR/Package.swift" "$WORKSPACE_DIR/Package.swift"
ln -s "$ROOT_DIR/Package.resolved" "$WORKSPACE_DIR/Package.resolved"
ln -s "$ROOT_DIR/Sources" "$WORKSPACE_DIR/Sources"
ln -s "$ROOT_DIR/Tests" "$WORKSPACE_DIR/Tests"

echo "Workspace: $WORKSPACE_DIR"

echo
echo "============================================================"
echo "[VERIFY] Confirming '$SCHEME' scheme is discoverable"
echo "============================================================"

rm -f "$SCHEME_LIST_STDERR_FILE"
SCHEME_LIST_JSON="$(cd "$WORKSPACE_DIR" && xcodebuild -list -json 2>"$SCHEME_LIST_STDERR_FILE")"
if [[ -z "$SCHEME_LIST_JSON" ]] || ! printf '%s' "$SCHEME_LIST_JSON" | jq -e \
    --arg scheme "$SCHEME" \
    '((.workspace.schemes // .project.schemes // []) | index($scheme)) != null' >/dev/null 2>&1; then
  echo "ERROR: scheme '$SCHEME' was not discovered from the package-only workspace at $WORKSPACE_DIR." >&2
  echo "xcodebuild -list -json stdout:" >&2
  echo "$SCHEME_LIST_JSON" >&2
  if [[ -s "$SCHEME_LIST_STDERR_FILE" ]]; then
    echo "xcodebuild -list -json stderr:" >&2
    cat "$SCHEME_LIST_STDERR_FILE" >&2
  fi
  exit 1
fi

echo "Scheme '$SCHEME' discovered."

echo
echo "============================================================"
echo "[DISCOVER] Selecting an iOS Simulator destination"
echo "============================================================"

select_newest_phone_simulator() {
  xcrun simctl list devices available -j 2>/dev/null | jq -r '
    .devices
    | to_entries[]
    | select(.key | test("com\\.apple\\.CoreSimulator\\.SimRuntime\\.iOS"))
    | . as $e
    | ($e.key | capture("iOS-(?<maj>[0-9]+)-(?<min>[0-9]+)")) as $v
    | $e.value[]
    | select(.isAvailable == true)
    | {
        runtime: $e.key,
        major: ($v.maj | tonumber),
        minor: ($v.min | tonumber),
        isPhone: (.deviceTypeIdentifier | test("iPhone")),
        name: .name,
        udid: .udid
      }
  ' | jq -s -r '
    sort_by([-.major, -.minor, (if .isPhone then 0 else 1 end), .name])
    | .[0]
    | if . == null then empty else "\(.udid)|\(.name)|\(.runtime)" end
  '
}

if [[ -n "${MARKDOWNKIT_IOS_SIMULATOR_UDID:-}" ]]; then
  SIMULATOR_UDID="$MARKDOWNKIT_IOS_SIMULATOR_UDID"
  SIMULATOR_NAME="$(xcrun simctl list devices available -j 2>/dev/null | jq -r \
    --arg udid "$SIMULATOR_UDID" \
    '.devices | to_entries[] | .value[] | select(.udid == $udid) | .name' | head -1)"
  if [[ -z "$SIMULATOR_NAME" ]]; then
    echo "ERROR: MARKDOWNKIT_IOS_SIMULATOR_UDID='$SIMULATOR_UDID' does not match any available simulator." >&2
    echo "Run 'xcrun simctl list devices available' to see valid UDIDs." >&2
    exit 1
  fi
  echo "Using operator-overridden simulator: $SIMULATOR_NAME ($SIMULATOR_UDID)"
else
  SELECTION="$(select_newest_phone_simulator)"
  if [[ -z "$SELECTION" ]]; then
    echo "ERROR: no available iOS Simulator device found via 'xcrun simctl list devices available -j'." >&2
    echo "Install an iOS simulator runtime, or set MARKDOWNKIT_IOS_SIMULATOR_UDID to an existing device UDID." >&2
    exit 1
  fi
  SIMULATOR_UDID="${SELECTION%%|*}"
  SELECTION_REST="${SELECTION#*|}"
  SIMULATOR_NAME="${SELECTION_REST%%|*}"
  SIMULATOR_RUNTIME="${SELECTION_REST#*|}"
  echo "Selected simulator: $SIMULATOR_NAME ($SIMULATOR_UDID) on $SIMULATOR_RUNTIME"
fi

DESTINATION="platform=iOS Simulator,id=$SIMULATOR_UDID"

echo
echo "============================================================"
echo "[DISCOVER] Enumerating XCTestCase suites (source scan, platform-agnostic)"
echo "============================================================"

ALL_SUITES=()
while IFS= read -r suite; do
  [[ -n "$suite" ]] && ALL_SUITES+=("$suite")
done < <(
  grep -rhoE 'class +[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*XCTestCase' \
    "$ROOT_DIR/Tests/MarkdownKitTests" --include='*.swift' \
    | sed -E 's/^class +([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
    | sort -u
)

if (( ${#ALL_SUITES[@]} == 0 )); then
  echo "ERROR: no XCTestCase suites discovered under Tests/MarkdownKitTests. Refusing to run an empty correctness gate." >&2
  exit 1
fi

EXCLUDED_SUITES=()
INCLUDED_SUITES=()
REQUIRED_UIKIT_SUITES=()

for suite in "${ALL_SUITES[@]}"; do
  case "$suite" in
    *Benchmark*)
      EXCLUDED_SUITES+=("$suite")
      ;;
    SnapshotTests|iOSSnapshotTests)
      EXCLUDED_SUITES+=("$suite")
      ;;
    *)
      INCLUDED_SUITES+=("$suite")
      ;;
  esac
done

while IFS= read -r test_file; do
  grep -qE '#(if|elseif).*(canImport\(UIKit\)|os\(iOS\))' "$test_file" || continue
  while IFS= read -r suite; do
    [[ -z "$suite" ]] && continue
    case "$suite" in
      *Benchmark*|SnapshotTests|iOSSnapshotTests)
        ;;
      *)
        REQUIRED_UIKIT_SUITES+=("$suite")
        ;;
    esac
  done < <(
    grep -hoE 'class +[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*XCTestCase' "$test_file" \
      | sed -E 's/^class +([A-Za-z_][A-Za-z0-9_]*).*/\1/'
  )
done < <(find "$ROOT_DIR/Tests/MarkdownKitTests" -type f -name '*.swift' -print | sort)

if (( ${#REQUIRED_UIKIT_SUITES[@]} == 0 )); then
  echo "ERROR: no UIKit-bearing XCTestCase suites were discovered. Refusing to run an iOS lane that cannot prove UIKit coverage." >&2
  exit 1
fi

SORTED_REQUIRED_UIKIT_SUITES=()
while IFS= read -r suite; do
  [[ -n "$suite" ]] && SORTED_REQUIRED_UIKIT_SUITES+=("$suite")
done < <(printf '%s\n' "${REQUIRED_UIKIT_SUITES[@]}" | sort -u)
REQUIRED_UIKIT_SUITES=("${SORTED_REQUIRED_UIKIT_SUITES[@]}")

if (( ${#INCLUDED_SUITES[@]} == 0 )); then
  echo "ERROR: discovery excluded every suite (benchmark/snapshot filters too broad?). Refusing to run an empty correctness gate." >&2
  exit 1
fi

join_with_comma() {
  local IFS=', '
  echo "$*"
}

echo "Discovered ${#ALL_SUITES[@]} suite(s) total."
echo "Excluded (benchmark suites + true snapshot suites, out of scope for this lane): $(join_with_comma "${EXCLUDED_SUITES[@]:-}")"
echo "Included iOS correctness suites (${#INCLUDED_SUITES[@]}): $(join_with_comma "${INCLUDED_SUITES[@]}")"
echo "UIKit-bearing suites required in the compiled test bundle (${#REQUIRED_UIKIT_SUITES[@]}): $(join_with_comma "${REQUIRED_UIKIT_SUITES[@]}")"

SKIP_TESTING_ARGS=()
for suite in "${EXCLUDED_SUITES[@]}"; do
  SKIP_TESTING_ARGS+=("-skip-testing:$TEST_TARGET/$suite")
done

echo
echo "============================================================"
echo "[VERIFY] Enumerating the compiled iOS test bundle"
echo "============================================================"

rm -f "$TEST_ENUMERATION_FILE" "$TEST_ENUMERATION_LOG_FILE"
if ! (
  cd "$WORKSPACE_DIR" && \
  xcodebuild test \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -skipMacroValidation \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    "${SKIP_TESTING_ARGS[@]}" \
    -enumerate-tests \
    -test-enumeration-style flat \
    -test-enumeration-format json \
    -test-enumeration-output-path "$TEST_ENUMERATION_FILE"
) >"$TEST_ENUMERATION_LOG_FILE" 2>&1; then
  echo "ERROR: xcodebuild could not enumerate the compiled iOS tests." >&2
  cat "$TEST_ENUMERATION_LOG_FILE" >&2
  exit 1
fi

if [[ ! -s "$TEST_ENUMERATION_FILE" ]] || ! jq -e \
    '((.errors // []) | length == 0) and
     (([.values[]?.enabledTests[]?
        | select(.identifier | split("/") | length >= 3)] | length) > 0)' \
    "$TEST_ENUMERATION_FILE" >/dev/null 2>&1; then
  echo "ERROR: iOS test enumeration was empty or reported errors." >&2
  cat "$TEST_ENUMERATION_FILE" >&2
  exit 1
fi

# Xcode may emit suite-only entries (for example a platform-gated suite with no
# compiled test methods). Count only identifiers shaped as target/suite/test.
ENUMERATED_TEST_COUNT="$(jq '[.values[]?.enabledTests[]?
  | select(.identifier | split("/") | length >= 3)] | length' "$TEST_ENUMERATION_FILE")"
MISSING_UIKIT_SUITES=()
for suite in "${REQUIRED_UIKIT_SUITES[@]}"; do
  if ! jq -e --arg prefix "$TEST_TARGET/$suite/" \
      'any(.values[]?.enabledTests[]?; .identifier | startswith($prefix))' \
      "$TEST_ENUMERATION_FILE" >/dev/null; then
    MISSING_UIKIT_SUITES+=("$suite")
  fi
done

if (( ${#MISSING_UIKIT_SUITES[@]} > 0 )); then
  echo "ERROR: compiled iOS test bundle is missing UIKit-bearing suite(s): $(join_with_comma "${MISSING_UIKIT_SUITES[@]}")" >&2
  exit 1
fi

echo "Compiled iOS test bundle enumerated $ENUMERATED_TEST_COUNT enabled test(s), including every required UIKit-bearing suite."

mkdir -p "$BUILD_LOG_DIR"
rm -f "$LOG_FILE"

echo
echo "============================================================"
echo "[START] iOS Simulator correctness lane"
echo "Scheme:       $SCHEME"
echo "Destination:  $DESTINATION"
echo "DerivedData:  $DERIVED_DATA_DIR"
echo "Log:          $LOG_FILE"
echo "Test timeout: default 60s / maximum 180s per test (identifies hangs by test, not by whole-suite timeout)"
echo "============================================================"

(
  cd "$WORKSPACE_DIR" && \
  xcodebuild test \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -skipMacroValidation \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 60 \
    -maximum-test-execution-time-allowance 180 \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    "${SKIP_TESTING_ARGS[@]}"
) 2>&1 | tee "$LOG_FILE"
XCODEBUILD_STATUS=${PIPESTATUS[0]}

if [[ "$XCODEBUILD_STATUS" -ne 0 ]]; then
  echo
  echo "[FAIL] xcodebuild test exited with status $XCODEBUILD_STATUS."
  exit 1
fi

RESTART_CRASH_MARKER='Restarting after unexpected exit, crash, or test timeout'
if grep -nF "$RESTART_CRASH_MARKER" "$LOG_FILE" >/dev/null 2>&1; then
  echo "ERROR: detected XCTest process restart/crash diagnostics in xcodebuild output." >&2
  echo "xcodebuild reported a test process restart after an unexpected exit, crash, or test timeout; this lane cannot be accepted as green." >&2
  grep -nF "$RESTART_CRASH_MARKER" "$LOG_FILE" >&2
  exit 1
fi

if ! grep -q '\*\* TEST SUCCEEDED \*\*' "$LOG_FILE"; then
  echo "ERROR: xcodebuild did not report '** TEST SUCCEEDED **'; treating as a failure." >&2
  exit 1
fi

# xcodebuild prints one or more "Executed N test(s)..." summary lines; guard
# against a destination/filter combination that silently runs zero tests.
EXECUTED_COUNT="$(grep -oE 'Executed [0-9]+ test' "$LOG_FILE" | grep -oE '[0-9]+' | sort -n | tail -1)"
if [[ -z "${EXECUTED_COUNT:-}" ]] || [[ "$EXECUTED_COUNT" -eq 0 ]]; then
  echo "ERROR: zero tests executed on the iOS Simulator lane. Treating as a failure." >&2
  exit 1
fi
if [[ "$EXECUTED_COUNT" -ne "$ENUMERATED_TEST_COUNT" ]]; then
  echo "ERROR: xcodebuild enumerated $ENUMERATED_TEST_COUNT enabled iOS test(s), but the run reported $EXECUTED_COUNT executed." >&2
  exit 1
fi

echo
echo "============================================================"
echo "[VERIFY] Scanning for private system-font fallback diagnostics"
echo "============================================================"

# A green "** TEST SUCCEEDED **" can still hide a real correctness bug: private
# descriptor names like ".SFUI"/".SFNS" round-tripping into CoreText make the
# simulator silently substitute Times New Roman instead of the intended
# system font, logging a "CoreText note: Client requested name ..." diagnostic
# rather than failing the test. Treat any of these as a hard failure so the
# lane stays a meaningful signal once the underlying font-handling bug (see
# tasks/todo.md "fix: derive system-font traits safely") regresses.
FONT_FALLBACK_PATTERN='\.SFUI|\.SFNS|Times ?New ?Roman|CoreText note: Client requested name'
if grep -nE "$FONT_FALLBACK_PATTERN" "$LOG_FILE" >/dev/null 2>&1; then
  echo "ERROR: detected private system-font fallback diagnostics in xcodebuild output." >&2
  echo "This means a private font descriptor was substituted (e.g. Times New Roman standing in for the system font); treat as a correctness regression, not log noise." >&2
  grep -nE "$FONT_FALLBACK_PATTERN" "$LOG_FILE" >&2
  exit 1
fi

echo "No private system-font fallback diagnostics detected."

echo
echo "iOS Simulator verification passed ($EXECUTED_COUNT test(s) executed on $SIMULATOR_NAME)."
