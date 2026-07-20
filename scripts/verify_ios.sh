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
#   - The hostless XCTest process injects a deterministic Mermaid image driver
#     before the lazy snapshotter is created. After the exact XCTest count
#     passes, this script assembles the SwiftPM demo executable into a signed
#     Simulator app and requires a real WebKit Mermaid render there.
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
EXPECTED_IOS_TEST_COUNT=565
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
DEMO_SCHEME="MarkdownKitDemo"
DEMO_PRODUCTS_DIR="$DERIVED_DATA_DIR/Build/Products/Debug-iphonesimulator"
DEMO_BUILD_LOG_FILE="$BUILD_LOG_DIR/ios-mermaid-smoke-build.log"
SMOKE_APP_DIR="$BUILD_LOG_DIR/MarkdownKitDemoSmoke.app"
SMOKE_BUNDLE_ID="com.anyuan.MarkdownKitDemoSmoke"
SMOKE_LAUNCH_ARGUMENT="--markdownkit-mermaid-smoke"
SMOKE_LOG_FILE="$BUILD_LOG_DIR/ios-mermaid-smoke.log"
SMOKE_LOG_PID=""
SMOKE_CLEANUP_ARMED=0

# This lane assumes a macOS runner with Xcode command line tools (xcodebuild,
# xcrun) and jq preinstalled, matching GitHub Actions' macOS images. jq is
# required (not optional) to parse `xcodebuild -list -json` and
# `simctl list devices -j` output; fail fast and loudly rather than falling
# back to fragile text parsing if any tool is missing.
for tool in xcodebuild xcrun jq codesign plutil ditto; do
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

IPHONE_SIMULATOR_SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null)" || {
  echo "ERROR: could not determine the active iPhone Simulator SDK version with 'xcrun --sdk iphonesimulator --show-sdk-version'." >&2
  exit 1
}
if [[ ! "$IPHONE_SIMULATOR_SDK_VERSION" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]]; then
  echo "ERROR: active iPhone Simulator SDK version '$IPHONE_SIMULATOR_SDK_VERSION' is not a supported major.minor version." >&2
  exit 1
fi
IPHONE_SIMULATOR_SDK_MAJOR="${BASH_REMATCH[1]}"
IPHONE_SIMULATOR_SDK_MINOR="${BASH_REMATCH[2]}"
TARGET_SIMULATOR_RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-${IPHONE_SIMULATOR_SDK_MAJOR}-${IPHONE_SIMULATOR_SDK_MINOR}"

select_sdk_matched_phone_simulator() {
  xcrun simctl list devices available -j 2>/dev/null | jq -r '
    .devices[$runtime] // []
    | map(
        select(.isAvailable == true)
        | {
            isPhone: ((.deviceTypeIdentifier // "") | test("iPhone")),
            name: .name,
            udid: .udid
          }
      )
    | sort_by([(if .isPhone then 0 else 1 end), .name, .udid])
    | .[0]
    | if . == null then empty else "\(.udid)|\(.name)|\($runtime)" end
  ' --arg runtime "$TARGET_SIMULATOR_RUNTIME"
}

if [[ -n "${MARKDOWNKIT_IOS_SIMULATOR_UDID:-}" ]]; then
  SIMULATOR_UDID="$MARKDOWNKIT_IOS_SIMULATOR_UDID"
  OVERRIDE_SELECTION="$(xcrun simctl list devices available -j 2>/dev/null | jq -r \
    --arg udid "$SIMULATOR_UDID" \
    '.devices
     | to_entries[]
     | . as $entry
     | $entry.value[]
     | select(.udid == $udid)
     | "\(.name)|\($entry.key)"' | head -1)"
  if [[ -z "$OVERRIDE_SELECTION" ]]; then
    echo "ERROR: MARKDOWNKIT_IOS_SIMULATOR_UDID='$SIMULATOR_UDID' does not match any available simulator." >&2
    echo "Run 'xcrun simctl list devices available' to see valid UDIDs." >&2
    exit 1
  fi
  SIMULATOR_NAME="${OVERRIDE_SELECTION%%|*}"
  SIMULATOR_RUNTIME="${OVERRIDE_SELECTION#*|}"
  echo "Using operator-overridden simulator: $SIMULATOR_NAME ($SIMULATOR_UDID) on $SIMULATOR_RUNTIME"
  echo "Active iPhone Simulator SDK $IPHONE_SIMULATOR_SDK_VERSION selects $TARGET_SIMULATOR_RUNTIME; the explicit override is allowed to differ."
else
  SELECTION="$(select_sdk_matched_phone_simulator)"
  if [[ -z "$SELECTION" ]]; then
    echo "ERROR: no available iOS Simulator device was found for active iPhone Simulator SDK $IPHONE_SIMULATOR_SDK_VERSION (runtime $TARGET_SIMULATOR_RUNTIME)." >&2
    echo "Install or create a device for that runtime, or set MARKDOWNKIT_IOS_SIMULATOR_UDID to an available device UDID." >&2
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
echo "[SETUP] Waiting for the selected iOS Simulator to fully boot"
echo "============================================================"

if ! xcrun simctl bootstatus "$SIMULATOR_UDID" -b; then
  echo "ERROR: simulator '$SIMULATOR_NAME' ($SIMULATOR_UDID) did not complete a full boot." >&2
  echo "Resolve the simulator boot failure, or set MARKDOWNKIT_IOS_SIMULATOR_UDID to an available device UDID." >&2
  exit 1
fi

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

print_mermaid_smoke_diagnostics() {
  if [[ -s "$DEMO_BUILD_LOG_FILE" ]]; then
    echo "MarkdownKitDemo smoke build log:" >&2
    cat "$DEMO_BUILD_LOG_FILE" >&2
  fi
  if [[ -s "$SMOKE_LOG_FILE" ]]; then
    echo "MarkdownKitDemo smoke simulator log:" >&2
    cat "$SMOKE_LOG_FILE" >&2
  fi
}

fail_mermaid_smoke() {
  echo "ERROR: $*" >&2
  print_mermaid_smoke_diagnostics
  exit 1
}

stop_mermaid_smoke_log_stream() {
  if [[ -n "${SMOKE_LOG_PID:-}" ]]; then
    if kill -0 "$SMOKE_LOG_PID" >/dev/null 2>&1; then
      kill "$SMOKE_LOG_PID" >/dev/null 2>&1 || true
    fi
    wait "$SMOKE_LOG_PID" >/dev/null 2>&1 || true
    SMOKE_LOG_PID=""
  fi
}

cleanup_mermaid_smoke() {
  local exit_status=$?
  trap - EXIT INT TERM

  if [[ "$SMOKE_CLEANUP_ARMED" -eq 1 ]]; then
    xcrun simctl terminate "$SIMULATOR_UDID" "$SMOKE_BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl uninstall "$SIMULATOR_UDID" "$SMOKE_BUNDLE_ID" >/dev/null 2>&1 || true
    stop_mermaid_smoke_log_stream
  fi

  exit "$exit_status"
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
if [[ "$ENUMERATED_TEST_COUNT" -ne "$EXPECTED_IOS_TEST_COUNT" ]]; then
  echo "ERROR: compiled iOS test bundle enumerated $ENUMERATED_TEST_COUNT enabled test(s); expected exactly $EXPECTED_IOS_TEST_COUNT." >&2
  echo "Update the reviewed release/test-count contract together with any intentional test inventory change." >&2
  exit 1
fi

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
echo "[START] iOS Simulator XCTest correctness contracts"
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
if [[ "$EXECUTED_COUNT" -ne "$ENUMERATED_TEST_COUNT" ]] || [[ "$EXECUTED_COUNT" -ne "$EXPECTED_IOS_TEST_COUNT" ]]; then
  echo "ERROR: xcodebuild enumerated $ENUMERATED_TEST_COUNT enabled iOS test(s), expected $EXPECTED_IOS_TEST_COUNT, but the run reported $EXECUTED_COUNT executed." >&2
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
echo "[PASS] iOS Simulator XCTest correctness contracts passed ($EXECUTED_COUNT test(s) executed on $SIMULATOR_NAME; Mermaid uses its injected deterministic backend in this hostless process)."

echo
echo "============================================================"
echo "[START] App-hosted real WebKit Mermaid smoke"
echo "Scheme:       $DEMO_SCHEME"
echo "Destination:  $DESTINATION"
echo "DerivedData:  $DERIVED_DATA_DIR (reuses the XCTest package build)"
echo "App bundle:   $SMOKE_APP_DIR"
echo "Log:          $SMOKE_LOG_FILE"
echo "============================================================"

SMOKE_CLEANUP_ARMED=1
trap cleanup_mermaid_smoke EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

rm -rf "$SMOKE_APP_DIR"
mkdir -p "$SMOKE_APP_DIR"
rm -f "$DEMO_BUILD_LOG_FILE" "$SMOKE_LOG_FILE"

if ! (
  cd "$WORKSPACE_DIR" && \
  xcodebuild build \
    -scheme "$DEMO_SCHEME" \
    -configuration Debug \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""
) >"$DEMO_BUILD_LOG_FILE" 2>&1; then
  fail_mermaid_smoke "xcodebuild could not build '$DEMO_SCHEME' for the selected iOS Simulator."
fi

DEMO_EXECUTABLE="$DEMO_PRODUCTS_DIR/MarkdownKitDemo"
MARKDOWNKIT_RESOURCE_BUNDLE="$DEMO_PRODUCTS_DIR/MarkdownKit_MarkdownKit.bundle"
if [[ ! -x "$DEMO_EXECUTABLE" ]]; then
  fail_mermaid_smoke "required MarkdownKitDemo executable is missing or not executable at '$DEMO_EXECUTABLE'."
fi
if [[ ! -d "$MARKDOWNKIT_RESOURCE_BUNDLE" ]]; then
  fail_mermaid_smoke "required MarkdownKit resource bundle is missing at '$MARKDOWNKIT_RESOURCE_BUNDLE'."
fi

if ! ditto "$DEMO_EXECUTABLE" "$SMOKE_APP_DIR/MarkdownKitDemo"; then
  fail_mermaid_smoke "could not copy the MarkdownKitDemo executable into the smoke app bundle."
fi

COPIED_RESOURCE_BUNDLES=0
for resource_bundle in "$DEMO_PRODUCTS_DIR"/*.bundle; do
  [[ -d "$resource_bundle" ]] || continue
  if ! ditto "$resource_bundle" "$SMOKE_APP_DIR/$(basename "$resource_bundle")"; then
    fail_mermaid_smoke "could not copy generated resource bundle '$resource_bundle' into the smoke app bundle."
  fi
  COPIED_RESOURCE_BUNDLES=$((COPIED_RESOURCE_BUNDLES + 1))
done

if [[ "$COPIED_RESOURCE_BUNDLES" -eq 0 ]]; then
  fail_mermaid_smoke "no top-level generated resource bundles were found in '$DEMO_PRODUCTS_DIR'."
fi
if [[ ! -d "$SMOKE_APP_DIR/MarkdownKit_MarkdownKit.bundle" ]]; then
  fail_mermaid_smoke "MarkdownKit_MarkdownKit.bundle was not copied into the smoke app bundle."
fi
if [[ ! -f "$SMOKE_APP_DIR/MarkdownKit_MarkdownKit.bundle/mermaid.min.js" ]]; then
  fail_mermaid_smoke "the smoke app is missing the bundled Mermaid runtime."
fi
if [[ ! -f "$SMOKE_APP_DIR/MarkdownKit_MarkdownKit.bundle/mermaid-bootstrap.html" ]]; then
  fail_mermaid_smoke "the smoke app is missing the Mermaid bootstrap document."
fi

cat >"$SMOKE_APP_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MarkdownKitDemo</string>
    <key>CFBundleIdentifier</key>
    <string>com.anyuan.MarkdownKitDemoSmoke</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MarkdownKitDemoSmoke</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>iPhoneSimulator</string>
    </array>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>MinimumOSVersion</key>
    <string>17.0</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <key>UILaunchScreen</key>
    <dict/>
</dict>
</plist>
PLIST

if ! plutil -lint "$SMOKE_APP_DIR/Info.plist" >/dev/null; then
  fail_mermaid_smoke "generated smoke app Info.plist is invalid."
fi
if ! codesign --force --sign - --timestamp=none "$SMOKE_APP_DIR"; then
  fail_mermaid_smoke "could not ad-hoc sign the assembled smoke app bundle."
fi
if ! codesign --verify --deep --strict --verbose=2 "$SMOKE_APP_DIR"; then
  fail_mermaid_smoke "ad-hoc signature verification failed for the assembled smoke app bundle."
fi

if ! xcrun simctl uninstall "$SIMULATOR_UDID" "$SMOKE_BUNDLE_ID" >/dev/null 2>&1; then
  echo "No stale '$SMOKE_BUNDLE_ID' app was installed on $SIMULATOR_NAME."
fi
if ! xcrun simctl install "$SIMULATOR_UDID" "$SMOKE_APP_DIR"; then
  fail_mermaid_smoke "could not install the assembled smoke app bundle."
fi

xcrun simctl spawn "$SIMULATOR_UDID" log stream \
  --style compact \
  --predicate 'process == "MarkdownKitDemo"' \
  >"$SMOKE_LOG_FILE" 2>&1 &
SMOKE_LOG_PID=$!
sleep 1
if ! kill -0 "$SMOKE_LOG_PID" >/dev/null 2>&1; then
  wait "$SMOKE_LOG_PID" >/dev/null 2>&1 || true
  SMOKE_LOG_PID=""
  fail_mermaid_smoke "simulator-scoped log stream exited before the smoke app launched."
fi

if ! xcrun simctl launch \
  "$SIMULATOR_UDID" \
  "$SMOKE_BUNDLE_ID" \
  --args \
  "$SMOKE_LAUNCH_ARGUMENT"; then
  fail_mermaid_smoke "could not launch '$SMOKE_BUNDLE_ID' with '$SMOKE_LAUNCH_ARGUMENT'."
fi

SMOKE_PASS_MARKER="MARKDOWNKIT_IOS_MERMAID_SMOKE_PASS"
SMOKE_FAIL_MARKER="MARKDOWNKIT_IOS_MERMAID_SMOKE_FAIL"
SMOKE_DEADLINE=$(( $(date +%s) + 60 ))
SMOKE_PASSED=0
while [[ "$(date +%s)" -lt "$SMOKE_DEADLINE" ]]; do
  SMOKE_FAIL_COUNT="$(grep -cF "$SMOKE_FAIL_MARKER" "$SMOKE_LOG_FILE" || true)"
  SMOKE_PASS_COUNT="$(grep -cF "$SMOKE_PASS_MARKER" "$SMOKE_LOG_FILE" || true)"

  if [[ "$SMOKE_FAIL_COUNT" -ne 0 ]]; then
    fail_mermaid_smoke "the smoke app emitted '$SMOKE_FAIL_MARKER'."
  fi
  if [[ "$SMOKE_PASS_COUNT" -gt 1 ]]; then
    fail_mermaid_smoke "the smoke app emitted '$SMOKE_PASS_MARKER' more than once."
  fi
  if [[ "$SMOKE_PASS_COUNT" -eq 1 ]]; then
    SMOKE_PASSED=1
    break
  fi

  sleep 1
done

if [[ "$SMOKE_PASSED" -ne 1 ]]; then
  fail_mermaid_smoke "timed out waiting 60 seconds for '$SMOKE_PASS_MARKER'."
fi

sleep 1
SMOKE_FAIL_COUNT="$(grep -cF "$SMOKE_FAIL_MARKER" "$SMOKE_LOG_FILE" || true)"
SMOKE_PASS_COUNT="$(grep -cF "$SMOKE_PASS_MARKER" "$SMOKE_LOG_FILE" || true)"
if [[ "$SMOKE_FAIL_COUNT" -ne 0 ]] || [[ "$SMOKE_PASS_COUNT" -ne 1 ]]; then
  fail_mermaid_smoke "the smoke app did not emit exactly one '$SMOKE_PASS_MARKER' and no '$SMOKE_FAIL_MARKER'."
fi

echo "[PASS] App-hosted real WebKit Mermaid smoke emitted exactly one $SMOKE_PASS_MARKER marker."
