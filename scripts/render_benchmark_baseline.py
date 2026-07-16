#!/usr/bin/env python3
"""Render the authoritative benchmark baseline documentation.

This script is the *only* place that turns
`Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json` into prose. It is
dependency-free (standard library only) so it can run in any CI job or local
shell without a package install step.

Usage:
    python3 scripts/render_benchmark_baseline.py            # write docs/BENCHMARK_BASELINE.md
    python3 scripts/render_benchmark_baseline.py --check     # verify it is already up to date

`--check` never rewrites the file. It exits non-zero with a concise message
when the generated content would differ from what's on disk, so CI can catch
a baseline JSON edit that wasn't followed by a regeneration.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
BASELINE_JSON_PATH = REPO_ROOT / "Tests" / "MarkdownKitTests" / "Fixtures" / "benchmark_baseline.json"
BASELINE_JSON_RELATIVE = "Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json"
OUTPUT_DOC_PATH = REPO_ROOT / "docs" / "BENCHMARK_BASELINE.md"
OUTPUT_DOC_RELATIVE = "docs/BENCHMARK_BASELINE.md"

SUPPORTED_SCHEMA_VERSION = 1

# Groups are rendered in this fixed order, independent of JSON array order,
# so regeneration is deterministic even if measurements are reordered/added.
GROUP_ORDER = ["core.parse", "core.layout", "core.cache", "deep.concurrency"]
GROUP_TITLES = {
    "core.parse": "Parse",
    "core.layout": "Layout",
    "core.cache": "Cache",
    "deep.concurrency": "Concurrency",
}


class BaselineValidationError(ValueError):
    """Raised when the baseline JSON fails schema validation."""


def load_baseline(path: Path) -> dict[str, Any]:
    try:
        raw_text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise BaselineValidationError(f"Could not read baseline JSON at {path}: {error}") from error

    try:
        data = json.loads(raw_text)
    except json.JSONDecodeError as error:
        raise BaselineValidationError(f"Baseline JSON at {path} is not valid JSON: {error}") from error

    validate_baseline(data)
    return data


def _has_control_characters(value: str) -> bool:
    """True if `value` contains a newline/tab/other control character.

    Rendered fields land in single-line Markdown constructs (headings, table
    rows, inline code). A field with an embedded control character — most
    importantly `\n` — could otherwise inject arbitrary extra Markdown lines
    (a fake heading, an extra table row, a stray code fence) into the
    generated document.
    """
    return any(ord(ch) < 0x20 or ord(ch) == 0x7F for ch in value)


def _require_non_empty_string(value: Any, field: str, errors: list[str]) -> None:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{field} must be a non-empty string.")
        return
    if _has_control_characters(value):
        errors.append(f"{field} must be a single line with no control characters.")


def _require_no_forbidden_characters(value: Any, field: str, forbidden: str, errors: list[str]) -> None:
    """Reject characters that would corrupt the specific Markdown construct
    `field` is rendered into (e.g. a backtick inside a code span, or a pipe
    inside a table cell), on top of the general single-line contract above.
    """
    if not isinstance(value, str):
        return
    for char in forbidden:
        if char in value:
            errors.append(f"{field} must not contain the {char!r} character.")


def _require_positive_int(value: Any, field: str, errors: list[str]) -> None:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        errors.append(f"{field} must be a positive integer.")


def _require_positive_number(value: Any, field: str, errors: list[str]) -> None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        errors.append(f"{field} must be a positive number.")
        return
    if isinstance(value, float) and not math.isfinite(value):
        errors.append(f"{field} must be a finite number.")
        return
    if value <= 0:
        errors.append(f"{field} must be a positive number.")


def validate_baseline(data: Any) -> None:
    errors: list[str] = []

    if not isinstance(data, dict):
        raise BaselineValidationError("Baseline JSON root must be an object.")

    if data.get("schemaVersion") != SUPPORTED_SCHEMA_VERSION:
        errors.append(
            f"schemaVersion must equal {SUPPORTED_SCHEMA_VERSION}, "
            f"found {data.get('schemaVersion')!r}."
        )

    _require_non_empty_string(data.get("version"), "version", errors)
    _require_no_forbidden_characters(data.get("version"), "version", "`", errors)
    _require_non_empty_string(data.get("recordedAt"), "recordedAt", errors)
    _require_non_empty_string(data.get("commit"), "commit", errors)
    _require_no_forbidden_characters(data.get("commit"), "commit", "`", errors)

    platform = data.get("platform")
    if not isinstance(platform, dict):
        errors.append("platform must be an object.")
        platform = {}
    for field in ("os", "arch", "device"):
        _require_non_empty_string(platform.get(field), f"platform.{field}", errors)

    harness = data.get("harness")
    if not isinstance(harness, dict):
        errors.append("harness must be an object.")
        harness = {}
    _require_positive_int(harness.get("warmupIterations"), "harness.warmupIterations", errors)
    _require_positive_int(harness.get("measureIterations"), "harness.measureIterations", errors)
    _require_non_empty_string(harness.get("clock"), "harness.clock", errors)
    _require_no_forbidden_characters(harness.get("clock"), "harness.clock", "`", errors)

    policy = data.get("policy")
    if not isinstance(policy, dict):
        errors.append("policy must be an object.")
        policy = {}
    _require_positive_number(policy.get("maxSlowdownFactor"), "policy.maxSlowdownFactor", errors)
    _require_positive_number(
        policy.get("absoluteSlackMilliseconds"), "policy.absoluteSlackMilliseconds", errors
    )

    measurements = data.get("measurements")
    if not isinstance(measurements, list) or not measurements:
        errors.append("measurements must be a non-empty array.")
        measurements = []

    seen_keys: set[str] = set()
    present_groups: set[str] = set()
    for index, measurement in enumerate(measurements):
        if not isinstance(measurement, dict):
            errors.append(f"measurements[{index}] must be an object.")
            continue

        key = measurement.get("key")
        group = measurement.get("group")
        average = measurement.get("averageMilliseconds")

        _require_non_empty_string(key, f"measurements[{index}].key", errors)
        _require_no_forbidden_characters(key, f"measurements[{index}].key", "`|", errors)
        if isinstance(key, str):
            if key in seen_keys:
                errors.append(f"Duplicate measurement key '{key}'.")
            seen_keys.add(key)

        if group not in GROUP_ORDER:
            errors.append(
                f"measurements[{index}] ('{key}') has unsupported group {group!r}; "
                f"expected one of {GROUP_ORDER}."
            )
        else:
            present_groups.add(group)

        _require_positive_number(average, f"measurements[{index}] ('{key}').averageMilliseconds", errors)

    for required_group in GROUP_ORDER:
        if required_group not in present_groups:
            errors.append(f"Missing required group '{required_group}'.")

    if errors:
        details = "\n".join(f"  - {error}" for error in errors)
        raise BaselineValidationError(f"Baseline JSON failed schema validation:\n{details}")


def format_ms(value: float) -> str:
    return f"{value:g}ms"


def render_markdown(data: dict[str, Any]) -> str:
    measurements_by_group: dict[str, list[dict[str, Any]]] = {group: [] for group in GROUP_ORDER}
    for measurement in data["measurements"]:
        measurements_by_group[measurement["group"]].append(measurement)
    for group_measurements in measurements_by_group.values():
        group_measurements.sort(key=lambda m: m["key"])

    lines: list[str] = []
    lines.append("# MarkdownKit Benchmark Baseline")
    lines.append("")
    lines.append(
        "> **Generated file — do not hand-edit.** Produced by "
        "`scripts/render_benchmark_baseline.py` from "
        f"[`{BASELINE_JSON_RELATIVE}`]({'../' + BASELINE_JSON_RELATIVE}), the single "
        "machine-readable source of truth consumed by both this document and "
        "`BenchmarkRegressionGuard` in the Swift test target. Edit the JSON and rerun "
        "`python3 scripts/render_benchmark_baseline.py` to refresh this file."
    )
    lines.append("")
    lines.append(f"**Version**: `{data['version']}` · **Recorded**: {data['recordedAt']} · **Commit**: `{data['commit']}`")
    lines.append("")
    platform = data["platform"]
    lines.append(f"**Platform**: {platform['os']} · {platform['arch']} ({platform['device']})")
    harness = data["harness"]
    lines.append(
        f"**Harness**: `BenchmarkHarness` (warmup={harness['warmupIterations']}, "
        f"iterations={harness['measureIterations']}, clock=`{harness['clock']}`)"
    )
    lines.append("")
    policy = data["policy"]
    lines.append("## Regression Policy")
    lines.append("")
    lines.append(
        f"`BenchmarkRegressionGuard` fails a benchmark when its measured average exceeds:"
    )
    lines.append("")
    lines.append("```")
    lines.append(
        "budget = max(baseline * maxSlowdownFactor, baseline + absoluteSlackMilliseconds)"
    )
    lines.append("```")
    lines.append("")
    lines.append(f"* `maxSlowdownFactor` = {policy['maxSlowdownFactor']:g}")
    lines.append(f"* `absoluteSlackMilliseconds` = {policy['absoluteSlackMilliseconds']:g}")
    lines.append("")
    lines.append(
        "> Detailed per-phase win attribution + historical analysis (archival, not "
        "authoritative): [`BENCHMARK_POST_PHASE_6.md`](BENCHMARK_POST_PHASE_6.md)"
    )
    lines.append("")

    for group in GROUP_ORDER:
        group_measurements = measurements_by_group[group]
        if not group_measurements:
            continue
        lines.append(f"## {GROUP_TITLES[group]} (`{group}`)")
        lines.append("")
        lines.append("| Key | Average |")
        lines.append("|---|---:|")
        for measurement in group_measurements:
            lines.append(f"| `{measurement['key']}` | {format_ms(measurement['averageMilliseconds'])} |")
        lines.append("")

    lines.append("## Reproduction")
    lines.append("")
    lines.append("```bash")
    lines.append("bash scripts/verify_benchmarks.sh")
    lines.append("")
    lines.append("# Or individually:")
    lines.append('swift test --filter "MarkdownKitBenchmarkTests/testBenchmarkFullReport"')
    lines.append('swift test --filter "BenchmarkNodeTypeTests/testDeepBenchmarkFullReport"')
    lines.append('swift test --filter "BenchmarkNodeTypeTests/testPerSyntaxTieredBenchmark"')
    lines.append('swift test --filter "BenchmarkCacheTests"')
    lines.append("```")
    lines.append("")

    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify docs/BENCHMARK_BASELINE.md is up to date without rewriting it.",
    )
    args = parser.parse_args(argv)

    try:
        data = load_baseline(BASELINE_JSON_PATH)
    except BaselineValidationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    rendered = render_markdown(data)

    if args.check:
        try:
            existing: str | None = OUTPUT_DOC_PATH.read_text(encoding="utf-8")
        except OSError:
            existing = None

        if existing != rendered:
            reason = "missing" if existing is None else "stale"
            print(
                f"error: {OUTPUT_DOC_RELATIVE} is {reason} relative to {BASELINE_JSON_RELATIVE}.\n"
                f"Run: python3 scripts/render_benchmark_baseline.py",
                file=sys.stderr,
            )
            return 1

        print(f"{OUTPUT_DOC_RELATIVE} is up to date with {BASELINE_JSON_RELATIVE}.")
        return 0

    try:
        OUTPUT_DOC_PATH.write_text(rendered, encoding="utf-8")
    except OSError as error:
        print(f"error: Could not write {OUTPUT_DOC_RELATIVE}: {error}", file=sys.stderr)
        return 1

    print(f"Wrote {OUTPUT_DOC_RELATIVE} from {BASELINE_JSON_RELATIVE}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
