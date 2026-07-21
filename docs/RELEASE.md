# Release Procedure

This is the release-owner procedure for a tag-only MarkdownKit release. It is deliberately
separate from daily verification: do not substitute `verify_all.sh --full` for this matrix.

## Preconditions

Use Xcode 26.4.1 (build 17E202). Verify the selected developer directory, SDKs, and Simulator
runtime before creating a release candidate. Run the procedure in one Bash shell; the first command
enables fail-fast handling for every later assertion:

```bash
set -euo pipefail

xcodebuild -version
xcrun --sdk macosx --show-sdk-version
xcrun --sdk iphonesimulator --show-sdk-version
xcrun simctl list runtimes
command -v bash git swift xcodebuild xcrun python3 jq cmp uname mktemp gh awk sleep \
    codesign plutil ditto
```

The expected Xcode output is `Xcode 26.4.1` and `Build version 17E202`. The macOS SDK and active
iPhone Simulator SDK must be from that Xcode. `verify_ios.sh` selects an available iPhone
Simulator whose runtime matches the active iPhone Simulator SDK (currently iOS 26.4). Do not set
`MARKDOWNKIT_IOS_SIMULATOR_UDID` to a device on a different runtime.

The guarded benchmark baseline was recorded on macOS arm64 Apple Silicon. Run the benchmark gate
on a quiet arm64 host without competing builds or indexing work:

```bash
test "$(uname -m)" = "arm64"
```

Start from a clean, synchronized `main`, and confirm that the version tag does not already exist
locally or on `origin`:

```bash
VERSION=0.4.0
TAG="v$VERSION"

test -z "$(git status --porcelain)"
git fetch origin --prune --tags
git switch main
git pull --ff-only origin main
test "$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')" = "origin/main"
test "$(git rev-parse HEAD)" = "$(git rev-parse '@{upstream}')"
test -z "$(git status --porcelain)"

if git show-ref --verify --quiet "refs/tags/$TAG"; then
    echo "Local tag already exists: $TAG" >&2
    exit 1
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}"; then
    echo "Remote tag already exists: $TAG" >&2
    exit 1
fi
```

Prepare and review the release content, create the release commit on `main`, and record its exact
commit before running the gates:

```bash
RELEASE_SHA="$(git rev-parse HEAD)"
test -z "$(git status --porcelain)"
git log -1 --oneline "$RELEASE_SHA"
```

`git status --short` must be empty. All verification below is read-only with respect to tracked
release inputs. Do not use API `--record`, refresh benchmark or provenance metadata, or replace
committed snapshot baselines while verifying a release. The determinism gate temporarily records
images only inside its restore-on-exit transaction.

## Check-only matrix

Run these commands in order from the repository root. The counts below are the current expected
results and make a silent partial run a failure.

| Gate | Command | Expected result |
| --- | --- | --- |
| Package manifest | `swift package describe` | Describes the MarkdownKit package successfully. |
| Package build | `swift build` | Succeeds. |
| Consumer import smoke | `swift test --filter PublicAPISmokeTests` | 10 tests. |
| Provenance | `bash scripts/verify_provenance.sh` | Succeeds without refreshing provenance. |
| macOS public API | `bash scripts/verify_public_api.sh --platform macos --check` | 453 symbols / 599 relationships. |
| Fast correctness | `bash scripts/verify_fast.sh` | 618 tests; 637 discoverable tests. |
| Documentation freshness | `bash scripts/check_doc_freshness.sh` | 637 discoverable tests. |
| Snapshot visual contract | `bash scripts/verify_snapshots.sh --visual` | 4 tests and 4 committed PNG baselines. |
| Snapshot determinism | `bash scripts/verify_snapshots.sh --determinism` | Record 4 expected missing-reference failures, then verify 4 tests. |
| iOS Simulator correctness | `bash scripts/verify_ios.sh` | Exactly 678 XCTest tests, then exactly one PASS marker from an app-hosted `MarkdownView` Mermaid fence using real WebKit. |
| iOS Simulator public API | `bash scripts/verify_public_api.sh --platform ios-simulator --check` | arm64 and x86_64 each match 454 symbols / 610 relationships. |
| Benchmarks (last) | `bash scripts/verify_benchmarks.sh` | Baseline freshness and 13 canonical isolated Release workloads succeed; the prepared-content guard passes. |

The visual snapshot command compares against committed PNGs. Do not regenerate or replace those
PNGs during release verification. The determinism command is different: it temporarily empties
the snapshot directory, records four fresh images, verifies them in the same environment, then
restores the original directory and its Git status. Its temporary recording is not a baseline
update.

The iOS gate intentionally does not create `WKWebView` in the app-less XCTest process. Its 10
Mermaid adapter tests inject deterministic image generation before the lazy snapshotter is
constructed while retaining production FIFO/cache/cancellation/timeout ownership. After the exact
678-test contract passes, the script reuses the package build to assemble, sign, install, and
launch the SwiftPM demo product as a real Simulator app. That additional smoke must emit exactly
one PASS marker and no FAIL marker after a Mermaid fence enters public `MarkdownView`, is extracted
by the default plugin chain, and reaches a registry-backed real-WebKit adapter. It is not part of
the XCTest count.

After the matrix, confirm that the candidate did not change and that the tree is still clean:

```bash
test "$(git rev-parse HEAD)" = "$RELEASE_SHA"
test -z "$(git status --porcelain)"
```

## Publish the release commit and tag

Push the release commit, then wait for all three CI jobs for `RELEASE_SHA`: `verify`,
`verify-snapshots`, and `verify-ios`. Review the visual snapshot signal even though that CI step
is intentionally non-blocking on the moving macOS runner image. Do not tag until the required CI
jobs are complete and acceptable.

```bash
git push origin "$RELEASE_SHA:refs/heads/main"
test "$(git ls-remote origin refs/heads/main | awk '{print $1}')" = "$RELEASE_SHA"

RUN_ID=""
for attempt in {1..60}; do
    RUN_ID="$(gh run list --repo AnYuan/MarkdownKit --workflow ci.yml --branch main \
        --commit "$RELEASE_SHA" --event push --limit 1 \
        --json databaseId --jq '.[0].databaseId // empty')"
    test -n "$RUN_ID" && break
    sleep 5
done
test -n "$RUN_ID"
test "$(gh run view "$RUN_ID" --repo AnYuan/MarkdownKit \
    --json headSha --jq '.headSha')" = "$RELEASE_SHA"
gh run watch "$RUN_ID" --repo AnYuan/MarkdownKit --exit-status
test -z "$(gh run view "$RUN_ID" --repo AnYuan/MarkdownKit \
    --json jobs --jq '[.jobs[] | select(.conclusion != "success") | .name] | join(",")')"

VISUAL_STEP_CONCLUSION="$(gh run view "$RUN_ID" --repo AnYuan/MarkdownKit \
    --json jobs \
    --jq '[.jobs[].steps[]
        | select(.name == "Snapshot visual regression (non-blocking, moving CI image)")
        | .conclusion] | unique | join(",")')"
test "$VISUAL_STEP_CONCLUSION" = "success"
```

Create the annotated tag only after CI is complete. It must target the exact verified release
commit:

```bash
git tag -a "$TAG" "$RELEASE_SHA" -m "Release $TAG"
LOCAL_TAG_OBJECT="$(git rev-parse "refs/tags/$TAG")"
test "$(git cat-file -t "$LOCAL_TAG_OBJECT")" = "tag"
test "$(git rev-parse "refs/tags/$TAG^{}")" = "$RELEASE_SHA"

git push origin "refs/tags/$TAG:refs/tags/$TAG"

REMOTE_TAG_OBJECT="$(git ls-remote --tags origin "refs/tags/$TAG" | awk '{print $1}')"
REMOTE_PEELED_SHA="$(git ls-remote --tags origin "refs/tags/$TAG^{}" | awk '{print $1}')"
test "$REMOTE_TAG_OBJECT" = "$LOCAL_TAG_OBJECT"
test "$REMOTE_PEELED_SHA" = "$RELEASE_SHA"
```

Creating a GitHub Release is optional follow-up work; it is not part of this tag-only release.

## Abort and fix-forward rules

- If a local gate or required CI job fails, do not create or push the tag. Diagnose the failure,
  make a new release commit, update `RELEASE_SHA`, and rerun the complete matrix and CI.
- If the candidate changes after verification, abort the tag step and rerun from the new commit.
- Never move, delete-and-recreate, or reuse a pushed tag. If a published release needs a fix,
  ship a new version and a new immutable tag.
