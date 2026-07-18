#!/usr/bin/env bash
#
# Extract MarkdownKit's source-declared public API with SwiftPM, then compare
# it to a platform-specific committed baseline. The tracked Xcode project is
# intentionally never used here.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: bash scripts/verify_public_api.sh --platform macos|ios-simulator --check|--record

Extracts MarkdownKit's public Swift symbol graph through SwiftPM and compares
it with the selected committed baseline. --record intentionally replaces that
baseline after a reviewed API/toolchain change; --check never modifies it.
EOF
}

PLATFORM=""
MODE=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --platform)
      if [[ "$#" -lt 2 ]]; then
        echo "ERROR: --platform requires macos or ios-simulator." >&2
        usage >&2
        exit 2
      fi
      if [[ -n "$PLATFORM" ]]; then
        echo "ERROR: --platform may be specified only once." >&2
        exit 2
      fi
      PLATFORM="$2"
      shift 2
      ;;
    --check|--record)
      if [[ -n "$MODE" ]]; then
        echo "ERROR: choose exactly one of --check or --record." >&2
        exit 2
      fi
      MODE="$1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument '$1'." >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$PLATFORM" != "macos" && "$PLATFORM" != "ios-simulator" ]]; then
  echo "ERROR: --platform must be macos or ios-simulator." >&2
  usage >&2
  exit 2
fi
if [[ -z "$MODE" ]]; then
  echo "ERROR: choose exactly one of --check or --record." >&2
  usage >&2
  exit 2
fi

for tool in cmp python3 swift xcrun uname mktemp; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' was not found on PATH." >&2
    exit 1
  fi
done

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  arm64|x86_64)
    ;;
  *)
    echo "ERROR: unsupported host architecture '$HOST_ARCH'." >&2
    exit 1
    ;;
esac

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/markdownkit-public-api.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

MODULE_NAME="MarkdownKit"
BASELINE_PATH=""
SDK=""

if [[ "$PLATFORM" == "macos" ]]; then
  SDK="$(xcrun --show-sdk-path --sdk macosx)"
  BASELINE_PATH="$ROOT_DIR/API/PublicAPI/macos.json"
else
  SDK="$(xcrun --show-sdk-path --sdk iphonesimulator)"
  BASELINE_PATH="$ROOT_DIR/API/PublicAPI/ios-simulator.json"
fi

extract_graphs() {
  local architecture="$1"
  local output_dir="$2"
  local target=""

  if [[ "$PLATFORM" == "macos" ]]; then
    target="${architecture}-apple-macos26.0"
  else
    target="${architecture}-apple-ios17.0-simulator"
  fi

  echo "============================================================"
  echo "[BUILD] Public API symbol graph ($PLATFORM, $architecture)"
  echo "============================================================"
  swift build \
    --target "$MODULE_NAME" \
    --triple "$target" \
    --sdk "$SDK"

  # --show-bin-path must use the exact build flags above so its Modules
  # directory belongs to the platform and architecture being extracted.
  local bin_path
  bin_path="$(swift build \
    --show-bin-path \
    --target "$MODULE_NAME" \
    --triple "$target" \
    --sdk "$SDK")"
  local modules_dir="$bin_path/Modules"
  if [[ ! -d "$modules_dir" ]]; then
    echo "ERROR: matching SwiftPM Modules directory was not found: '$modules_dir'." >&2
    exit 1
  fi

  local include_dir
  for include_dir in \
    "$ROOT_DIR/.build/checkouts/swift-cmark/src/include" \
    "$ROOT_DIR/.build/checkouts/swift-cmark/extensions/include" \
    "$ROOT_DIR/.build/checkouts/swift-markdown/Sources/CAtomic/include"; do
    if [[ ! -d "$include_dir" ]]; then
      echo "ERROR: required symbol graph include directory is missing: '$include_dir'." >&2
      exit 1
    fi
  done

  mkdir -p "$output_dir"
  echo
  echo "============================================================"
  echo "[EXTRACT] Public Swift symbols ($target)"
  echo "============================================================"
  xcrun swift-symbolgraph-extract \
    -module-name "$MODULE_NAME" \
    -minimum-access-level public \
    -skip-inherited-docs \
    -skip-synthesized-members \
    -omit-extension-block-symbols \
    -sdk "$SDK" \
    -target "$target" \
    -I "$modules_dir" \
    -I "$ROOT_DIR/.build/checkouts/swift-cmark/src/include" \
    -I "$ROOT_DIR/.build/checkouts/swift-cmark/extensions/include" \
    -I "$ROOT_DIR/.build/checkouts/swift-markdown/Sources/CAtomic/include" \
    -output-dir "$output_dir"

  local base_graph="$output_dir/$MODULE_NAME.symbols.json"
  if [[ ! -s "$base_graph" ]]; then
    echo "ERROR: expected base graph was not emitted: '$base_graph'." >&2
    exit 1
  fi
}

ARCHITECTURES=("$HOST_ARCH")
if [[ "$PLATFORM" == "ios-simulator" ]]; then
  if [[ "$HOST_ARCH" == "arm64" ]]; then
    ARCHITECTURES+=("x86_64")
  else
    ARCHITECTURES+=("arm64")
  fi
fi

RAW_GRAPH_DIRS=()
CANDIDATE_BASELINES=()
for architecture in "${ARCHITECTURES[@]}"; do
  raw_graph_dir="$WORK_DIR/graphs-$architecture"
  extract_graphs "$architecture" "$raw_graph_dir"
  RAW_GRAPH_DIRS+=("$raw_graph_dir")

  echo
  echo "============================================================"
  echo "[$(printf '%s' "$MODE" | tr '[:lower:]' '[:upper:]' | sed 's/^--//')] Public API baseline ($PLATFORM, $architecture)"
  echo "============================================================"
  if [[ "$MODE" == "--check" ]]; then
    python3 "$ROOT_DIR/scripts/public_api_baseline.py" \
      --input-dir "$raw_graph_dir" \
      --baseline "$BASELINE_PATH" \
      --platform "$PLATFORM" \
      --check
  else
    candidate="$WORK_DIR/baseline-$architecture.json"
    python3 "$ROOT_DIR/scripts/public_api_baseline.py" \
      --input-dir "$raw_graph_dir" \
      --baseline "$candidate" \
      --platform "$PLATFORM" \
      --record
    CANDIDATE_BASELINES+=("$candidate")
  fi
done

if [[ "$MODE" == "--record" ]]; then
  primary_candidate="${CANDIDATE_BASELINES[0]}"
  for index in "${!CANDIDATE_BASELINES[@]}"; do
    candidate="${CANDIDATE_BASELINES[$index]}"
    if ! cmp -s "$primary_candidate" "$candidate"; then
      echo "ERROR: $PLATFORM public API differs between ${ARCHITECTURES[0]} and ${ARCHITECTURES[$index]}." >&2
      python3 "$ROOT_DIR/scripts/public_api_baseline.py" \
        --input-dir "${RAW_GRAPH_DIRS[$index]}" \
        --baseline "$primary_candidate" \
        --platform "$PLATFORM" \
        --check || true
      exit 1
    fi
  done

  python3 "$ROOT_DIR/scripts/public_api_baseline.py" \
    --input-dir "${RAW_GRAPH_DIRS[0]}" \
    --baseline "$BASELINE_PATH" \
    --platform "$PLATFORM" \
    --record
fi
