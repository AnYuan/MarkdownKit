#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path, PurePosixPath
from typing import Any

LOCK_PATH = PurePosixPath("ThirdParty/provenance.lock.json")
PACKAGE_MANIFEST_PATH = PurePosixPath("Package.swift")
PACKAGE_RESOLVED_PATH = PurePosixPath("Package.resolved")
NOTICE_PATH = PurePosixPath("THIRD_PARTY_NOTICES.md")
PROJECT_LICENSE_PATH = PurePosixPath("LICENSE")
INVENTORIES_DIR = PurePosixPath("ThirdParty/Inventories")
MERMAID_INVENTORY_PATH = PurePosixPath(
    "ThirdParty/Inventories/mermaid-10.9.5-umd-bundled-inventory.json"
)
MERMAID_REPORT_PATH = PurePosixPath(
    "ThirdParty/Licenses/mermaid/THIRD_PARTY_LICENSE_REPORT.md"
)
ALLOWED_SCOPES = {"runtime", "test"}
ALLOWED_CHECKED_IN_KINDS = {"license", "notice"}
EXPECTED_LOCK_KEYS = [
    "checked_in_files",
    "embedded_inventories",
    "package_resolved",
    "project_license",
    "project_notice",
    "schema_version",
    "vendored_resources",
]
# These digests are reviewed release-policy anchors. Updating the lock alone must
# not silently approve a different dependency graph or set of legal artifacts.
EXPECTED_PROJECT_LICENSE_SHA256 = (
    "cd72d4c8fad71306d4bed3fb41e694e015b2121c5b393ed06b23a3ea5dd4202d"
)
EXPECTED_PROJECT_NOTICE_SHA256 = (
    "f3c4289ac504bbc09dc1d85d601f5b6e0a0341a6f3dcdc858480569fcc001b38"
)
EXPECTED_PACKAGE_MANIFEST_SHA256 = (
    "6f6f329836311ed51ff52d7002c32bfe65bd5388482c405878091423d465cb3e"
)
EXPECTED_CHECKED_IN_FILES_POLICY_SHA256 = (
    "a0b9a2c1480cbcd5b4cb7bdfa2931f3574e0a2179de6280069443ac9adad03b8"
)
EXPECTED_PACKAGE_PROVENANCE_POLICY_SHA256 = (
    "e1f5bf9709c337fff9a2ffcf744d0d5178348d5c5b3923992d846e78aa332220"
)
EXPECTED_VENDORED_RESOURCE = {
    "id": "mermaid-dist",
    "path": "Sources/MarkdownKit/Resources/mermaid.min.js",
    "version": "10.9.5",
    "source_url": "https://unpkg.com/mermaid@10.9.5/dist/mermaid.min.js",
    "sha256": "616a109f19cd186842e11d45b35ac07456b3a75513310f6ea075351aa430b1e2",
    "license_identifier": "MIT",
    "license_files": ["ThirdParty/Licenses/mermaid/LICENSE"],
    "notice_files": [
        "ThirdParty/Licenses/mermaid/BUNDLE_NOTICES.txt",
        "ThirdParty/Licenses/mermaid/THIRD_PARTY_LICENSE_REPORT.md",
    ],
}
EXPECTED_MERMAID_INVENTORY_SHA256 = (
    "085cd421067d7007c7208afc3e1fed1ff15c57b63f4724ec25d30c090ba97f75"
)
EXPECTED_MERMAID_REPORT_SHA256 = (
    "1bafdaedd1dc0412f752fe42ff44825246286cf0bb36b61dbbd5b7564d34c397"
)
EXPECTED_MERMAID_POLICY_SHA256 = (
    "3ac06b65bcbba2139ea089e4a43df9b3a1912f31d282e0d5f411f5f1bb03e5a7"
)
EXPECTED_EMBEDDED_INVENTORY_DIGESTS = {
    "mathjaxswift": "e7ba8be40cdda89180ee07549b0579baf17566cf652883458daa9fc193d79ccf",
}
EXPECTED_VENDORED_RESOURCE_KEYS = [
    "id",
    "license_files",
    "license_identifier",
    "notice_files",
    "path",
    "runtime_relevance",
    "scope",
    "sha256",
    "source_url",
    "third_party_closure",
    "version",
]
EXPECTED_MERMAID_CLOSURE_KEYS = [
    "inventory_path",
    "inventory_sha256",
    "report_path",
    "report_sha256",
    "policy_sha256",
]
EXPECTED_MERMAID_INVENTORY_KEYS = [
    "schema_version",
    "resource_id",
    "resource_path",
    "project",
    "version",
    "tag",
    "commit",
    "package_manager",
    "inventory_basis",
    "authoritative_inputs",
    "rebuild_verification",
    "counts",
    "license_category_totals",
    "excluded_non_bundled_summary",
    "bundled_packages",
]
EXPECTED_MERMAID_AUTHORITATIVE_INPUTS = {
    "source_tarball_sha256": "883893d7ff503704d8f7356ee4c4a4d98f8286b4243803b1f92f7f004a54ccbd",
    "npm_tarball_sha256": "56aa81c2fa6f229f8cd9d8a66f7b2b895ad76db3c3abd9aac11e549204274cd5",
    "pnpm_lock_sha256": "22adf8b174c018035398709f56f107735687c6d0e485030b4771bbb6320fbff9",
}
EXPECTED_MERMAID_REBUILD_VERIFICATION = {
    "official_mermaid_min_js_sha256": "616a109f19cd186842e11d45b35ac07456b3a75513310f6ea075351aa430b1e2",
    "official_mermaid_min_js_bytes": 3338725,
    "rebuilt_mermaid_min_js_sha256": "616a109f19cd186842e11d45b35ac07456b3a75513310f6ea075351aa430b1e2",
    "rebuilt_mermaid_min_js_bytes": 3338725,
    "rebuild_matches_official": True,
}
EXPECTED_MERMAID_COUNTS = {
    "direct_dependencies_in_production_closure": 20,
    "total_unique_production_closure_packages": 108,
    "transitive_dependencies_in_production_closure": 88,
    "bundled_package_instances": 62,
    "bundled_direct_dependencies": 16,
    "bundled_transitive_dependencies": 46,
    "bundled_prebundle_packages": 3,
    "patched_bundled_packages": 1,
    "excluded_non_bundled_packages": 46,
    "optional_or_platform_only_packages": 1,
}
EXPECTED_MERMAID_LICENSE_TOTALS = {
    "MIT": 36,
    "ISC": 18,
    "BSD-3-Clause": 5,
    "Apache-2.0": 1,
    "EPL-2.0": 1,
    "(MPL-2.0 OR Apache-2.0)": 1,
}
EXPECTED_MERMAID_EXCLUDED_SUMMARY = {
    "not-bundled-aggregator-root": 2,
    "not-bundled-browser-conditional": 1,
    "not-bundled-cli-only": 5,
    "not-bundled-shipped-dev-tooling": 10,
    "not-bundled-type-only": 8,
    "not-bundled-unused-d3-subgraph": 15,
    "not-bundled-unused-direct": 1,
    "not-bundled-unused-micromark-subdep": 4,
}
EXPECTED_MERMAID_PACKAGE_KEYS = [
    "id",
    "name",
    "version",
    "resolved",
    "integrity",
    "dependency",
    "parents",
    "license_identifier",
    "redistribution_license_choice",
    "license_evidence",
    "license_notice_source_names",
    "patched",
    "patch_file",
    "bundle_presence",
    "bundle_reason",
    "bundle_evidence",
]
EXPECTED_MERMAID_LICENSE_EVIDENCE_KEYS = [
    "source_kind",
    "metadata_license_identifier",
    "inferred_license_identifier",
]
EXPECTED_MERMAID_BUNDLE_PRESENCE_KEYS = ["classification", "mode"]
ALLOWED_MERMAID_DEPENDENCIES = {"direct", "transitive"}
ALLOWED_MERMAID_LICENSE_EVIDENCE_KINDS = {
    "package-license-file",
    "package-json-license",
}
ALLOWED_MERMAID_BUNDLE_MODES = {"rollup-module", "embedded-prebundle"}
MERMAID_REPORT_ROW = re.compile(r"^\| `([^`]+)` \|")
MERMAID_REPORT_COVERAGE_ROW = re.compile(
    r"^  - `([^`]+)` \u2014 source `([^`]+)`; "
    r"(metadata|inferred) license `([^`]+)`$"
)


class ProvenanceError(RuntimeError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ProvenanceError(f"missing file: {path}") from exc
    except (OSError, UnicodeDecodeError) as exc:
        raise ProvenanceError(f"could not read file: {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ProvenanceError(f"invalid json: {path}: {exc}") from exc


def ensure_safe_relative_path(
    raw: Any,
    *,
    prefix: PurePosixPath | None = None,
) -> PurePosixPath:
    if not isinstance(raw, str) or not raw:
        raise ProvenanceError("empty path")
    if "\\" in raw:
        raise ProvenanceError(f"unsafe path with backslash: {raw}")
    path = PurePosixPath(raw)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise ProvenanceError(f"unsafe path: {raw}")
    if prefix is not None and path.parts[:len(prefix.parts)] != prefix.parts:
        raise ProvenanceError(f"path outside allowed prefix {prefix}: {raw}")
    return path


def require_regular_file(root: Path, relative_path: PurePosixPath) -> Path:
    candidate = root
    for part in relative_path.parts:
        candidate /= part
        if candidate.is_symlink():
            raise ProvenanceError(f"symlink is not allowed: {relative_path}")
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root)
    except FileNotFoundError as exc:
        raise ProvenanceError(f"missing file: {relative_path}") from exc
    except ValueError as exc:
        raise ProvenanceError(f"path escapes repository root: {relative_path}") from exc
    if not resolved.is_file():
        raise ProvenanceError(f"not a regular file: {relative_path}")
    return resolved


def inventory_regular_files(
    root: Path,
    relative_directory: PurePosixPath,
) -> tuple[set[str], list[str]]:
    directory = root
    for part in relative_directory.parts:
        directory /= part
        if directory.is_symlink():
            raise ProvenanceError(f"symlink is not allowed: {relative_directory}")
    try:
        resolved_directory = directory.resolve(strict=True)
        resolved_directory.relative_to(root)
    except FileNotFoundError as exc:
        raise ProvenanceError(f"missing directory: {relative_directory}") from exc
    except ValueError as exc:
        raise ProvenanceError(
            f"path escapes repository root: {relative_directory}"
        ) from exc
    if not resolved_directory.is_dir():
        raise ProvenanceError(f"not a directory: {relative_directory}")

    files: set[str] = set()
    errors: list[str] = []

    def visit(current: Path) -> None:
        try:
            children = sorted(current.iterdir(), key=lambda path: path.name)
        except OSError as exc:
            raise ProvenanceError(f"could not list directory: {current}: {exc}") from exc
        for child in children:
            relative = child.relative_to(root).as_posix()
            if child.is_symlink():
                errors.append(f"symlink is not allowed: {relative}")
            elif child.is_dir():
                visit(child)
            elif child.is_file():
                files.add(relative)
            else:
                errors.append(f"unsupported filesystem entry: {relative}")

    visit(resolved_directory)
    return files, errors


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise ProvenanceError(f"could not read file: {path}: {exc}") from exc
    return digest.hexdigest()


def canonical_sha256(value: Any) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def validate_policy_anchor(value: Any, label: str, expected: str) -> list[str]:
    actual = canonical_sha256(value)
    if actual == expected:
        return []
    return [f"{label} policy anchor {actual} != {expected}"]


def validate_key_order(
    value: Any,
    label: str,
    expected_keys: list[str],
) -> list[str]:
    if not isinstance(value, dict):
        return [f"{label} must be an object"]
    actual_keys = list(value.keys())
    if actual_keys != expected_keys:
        return [f"{label} keys {actual_keys} != {expected_keys}"]
    return []


def validate_sha256_string(value: Any, label: str) -> list[str]:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        return [f"{label} must be a lowercase sha256 hex string"]
    return []


def validate_exact_object(
    value: Any,
    label: str,
    expected: dict[str, Any],
) -> list[str]:
    errors = validate_key_order(value, label, list(expected))
    if not isinstance(value, dict):
        return errors
    for key, expected_value in expected.items():
        if value.get(key) != expected_value:
            errors.append(f"{label}.{key} {value.get(key)} != {expected_value}")
    return errors


def validate_object_list(
    value: Any,
    label: str,
    key_name: str,
) -> tuple[list[dict[str, Any]], list[str]]:
    if not isinstance(value, list):
        raise ProvenanceError(f"{label} must be a list")

    entries: list[dict[str, Any]] = []
    errors: list[str] = []
    keys: list[str] = []
    for index, item in enumerate(value):
        if not isinstance(item, dict):
            errors.append(f"{label}[{index}] must be an object")
            continue
        key = item.get(key_name)
        if not isinstance(key, str) or not key:
            errors.append(f"{label}[{index}] has invalid {key_name}")
            continue
        entries.append(item)
        keys.append(key)

    if keys != sorted(keys):
        errors.append(f"{label} not sorted by {key_name}")
    duplicates = sorted(key for key, count in Counter(keys).items() if count > 1)
    for duplicate in duplicates:
        errors.append(f"duplicate {label[:-1]} {duplicate}")
    return entries, errors


def validate_string_list(value: Any, label: str) -> tuple[list[str], list[str]]:
    if not isinstance(value, list):
        return [], [f"{label} must be a list"]

    items: list[str] = []
    errors: list[str] = []
    for index, item in enumerate(value):
        if not isinstance(item, str) or not item:
            errors.append(f"{label}[{index}] must be a non-empty string")
            continue
        items.append(item)
    if items != sorted(items):
        errors.append(f"{label} not sorted")
    duplicates = sorted(item for item, count in Counter(items).items() if count > 1)
    for duplicate in duplicates:
        errors.append(f"duplicate {label} entry {duplicate}")
    return items, errors


def normalize_pin(pin: dict[str, Any]) -> dict[str, Any]:
    for field in ("identity", "kind", "location"):
        if not isinstance(pin.get(field), str) or not pin[field]:
            raise ProvenanceError(f"pin has invalid {field}")
    state = pin.get("state")
    if not isinstance(state, dict) or not state:
        raise ProvenanceError(f"pin {pin.get('identity', '<unknown>')} has invalid state")
    if not isinstance(state.get("revision"), str) or not state["revision"]:
        raise ProvenanceError(f"pin {pin['identity']} has invalid revision")
    for key, value in state.items():
        if not isinstance(key, str) or not isinstance(value, str) or not value:
            raise ProvenanceError(f"pin {pin['identity']} has invalid state.{key}")
    return {
        "identity": pin["identity"],
        "kind": pin["kind"],
        "location": pin["location"],
        "state": {key: state[key] for key in sorted(state)},
    }


def describe_pin(pin: dict[str, Any]) -> str:
    state = pin["state"]
    if "version" in state:
        return f"{pin['identity']} {state['version']} ({state.get('revision', 'no-revision')})"
    if "branch" in state:
        return f"{pin['identity']} branch {state['branch']} ({state.get('revision', 'no-revision')})"
    return f"{pin['identity']} {state.get('revision', 'no-revision')}"


def diff_pin(expected: dict[str, Any], actual: dict[str, Any]) -> list[str]:
    changes: list[str] = []
    for field in ("kind", "location"):
        if expected[field] != actual[field]:
            changes.append(f"{field} {expected[field]} -> {actual[field]}")
    expected_state = expected["state"]
    actual_state = actual["state"]
    all_state_keys = sorted(set(expected_state) | set(actual_state))
    for key in all_state_keys:
        expected_value = expected_state.get(key)
        actual_value = actual_state.get(key)
        if expected_value != actual_value:
            changes.append(f"state.{key} {expected_value} -> {actual_value}")
    return changes


def validate_checked_in_files(root: Path, lock: dict[str, Any]) -> tuple[list[str], dict[str, dict[str, Any]]]:
    entries, errors = validate_object_list(
        lock.get("checked_in_files"),
        "checked_in_files",
        "path",
    )
    by_path: dict[str, dict[str, Any]] = {}
    for entry in entries:
        try:
            rel_path = ensure_safe_relative_path(
                entry["path"],
                prefix=PurePosixPath("ThirdParty/Licenses"),
            )
        except (KeyError, ProvenanceError) as exc:
            errors.append(str(exc))
            continue
        kind = entry.get("kind")
        if kind not in ALLOWED_CHECKED_IN_KINDS:
            errors.append(f"checked_in_file {entry.get('path')} has invalid kind {kind}")
        sha256 = entry.get("sha256")
        if (
            not isinstance(sha256, str)
            or len(sha256) != 64
            or any(character not in "0123456789abcdef" for character in sha256)
        ):
            errors.append(f"checked_in_file {entry.get('path')} has invalid sha256")
        source = entry.get("source")
        if not isinstance(source, str) or not source.startswith("https://"):
            errors.append(f"checked_in_file {entry.get('path')} has invalid source")
        normalization = entry.get("normalization")
        source_sha256 = entry.get("source_sha256")
        if normalization is not None:
            if not isinstance(normalization, str) or not normalization:
                errors.append(
                    f"checked_in_file {entry.get('path')} has invalid normalization"
                )
            if (
                not isinstance(source_sha256, str)
                or len(source_sha256) != 64
                or any(
                    character not in "0123456789abcdef"
                    for character in source_sha256
                )
            ):
                errors.append(
                    f"checked_in_file {entry.get('path')} has invalid source_sha256"
                )
        elif source_sha256 is not None:
            errors.append(
                f"checked_in_file {entry.get('path')} has source_sha256 without normalization"
            )
        try:
            disk_path = require_regular_file(root, rel_path)
        except ProvenanceError as exc:
            errors.append(str(exc))
        else:
            actual_hash = sha256_file(disk_path)
            if actual_hash != sha256:
                errors.append(
                    f"changed checked-in file {entry['path']}: sha256 {sha256} -> {actual_hash}"
                )
        by_path[entry["path"]] = entry
    return errors, by_path


def validate_package_resolved(root: Path, lock: dict[str, Any]) -> tuple[list[str], dict[str, dict[str, Any]]]:
    section = lock.get("package_resolved")
    if not isinstance(section, dict):
        raise ProvenanceError("package_resolved must be an object")
    errors: list[str] = []
    if section.get("path") != str(PACKAGE_RESOLVED_PATH):
        errors.append(
            f"package_resolved.path must be {PACKAGE_RESOLVED_PATH}, found {section.get('path')}"
        )

    actual_path = require_regular_file(root, PACKAGE_RESOLVED_PATH)
    actual = load_json(actual_path)
    if not isinstance(actual, dict):
        raise ProvenanceError("Package.resolved must be a json object")
    if section.get("version") != actual.get("version"):
        errors.append(
            f"Package.resolved version {section.get('version')} -> {actual.get('version')}"
        )
    if section.get("origin_hash") != actual.get("originHash"):
        errors.append(
            f"Package.resolved originHash {section.get('origin_hash')} -> {actual.get('originHash')}"
        )

    locked_pins_raw, locked_pin_errors = validate_object_list(
        section.get("pins"),
        "pins",
        "identity",
    )
    errors.extend(locked_pin_errors)

    locked_pins: dict[str, dict[str, Any]] = {}
    for pin in locked_pins_raw:
        try:
            normalized = normalize_pin(pin)
        except (KeyError, ProvenanceError) as exc:
            errors.append(str(exc))
            continue
        if pin.get("scope") not in ALLOWED_SCOPES:
            errors.append(f"pin {pin.get('identity')} has invalid scope {pin.get('scope')}")
        if not pin.get("runtime_relevance"):
            errors.append(f"pin {pin.get('identity')} missing runtime_relevance")
        if not pin.get("license_identifier"):
            errors.append(f"pin {pin.get('identity')} missing license_identifier")
        for field_name in ("license_files", "notice_files"):
            _, field_errors = validate_string_list(
                pin.get(field_name),
                f"pin {pin.get('identity')} {field_name}",
            )
            errors.extend(field_errors)
        locked_pins[normalized["identity"]] = normalized

    actual_pins_raw, actual_pin_errors = validate_object_list(
        actual.get("pins"),
        "Package.resolved pins",
        "identity",
    )
    errors.extend(actual_pin_errors)
    actual_pins: dict[str, dict[str, Any]] = {}
    for pin in actual_pins_raw:
        try:
            normalized = normalize_pin(pin)
        except ProvenanceError as exc:
            errors.append(str(exc))
            continue
        actual_pins[normalized["identity"]] = normalized

    locked_ids = set(locked_pins)
    actual_ids = set(actual_pins)
    for added in sorted(actual_ids - locked_ids):
        errors.append(f"added pin {describe_pin(actual_pins[added])}")
    for removed in sorted(locked_ids - actual_ids):
        errors.append(f"removed pin {describe_pin(locked_pins[removed])}")
    for identity in sorted(locked_ids & actual_ids):
        diffs = diff_pin(locked_pins[identity], actual_pins[identity])
        for diff in diffs:
            errors.append(f"changed pin {identity}: {diff}")
    return errors, locked_pins


def validate_vendored_resources(
    root: Path,
    lock: dict[str, Any],
) -> tuple[list[str], dict[str, dict[str, Any]]]:
    resources, errors = validate_object_list(
        lock.get("vendored_resources"),
        "vendored_resources",
        "id",
    )
    if len(resources) != 1:
        errors.append(f"expected 1 vendored resource, found {len(resources)}")

    by_id: dict[str, dict[str, Any]] = {}
    for resource in resources:
        resource_id = resource.get("id")
        errors.extend(
            validate_key_order(
                resource,
                f"vendored resource {resource_id}",
                EXPECTED_VENDORED_RESOURCE_KEYS,
            )
        )
        for field, expected_value in EXPECTED_VENDORED_RESOURCE.items():
            actual_value = resource.get(field)
            if actual_value != expected_value:
                errors.append(
                    f"vendored resource {resource_id} {field} "
                    f"{actual_value} != {expected_value}"
                )
        for field_name in ("license_files", "notice_files"):
            _, field_errors = validate_string_list(
                resource.get(field_name),
                f"vendored resource {resource_id} {field_name}",
            )
            errors.extend(field_errors)
        if not isinstance(resource.get("third_party_closure"), dict):
            errors.append(f"vendored resource {resource_id} missing third_party_closure")
        if resource.get("scope") != "runtime":
            errors.append(
                f"vendored resource {resource_id} has invalid scope "
                f"{resource.get('scope')}"
            )
        if not resource.get("runtime_relevance"):
            errors.append(f"vendored resource {resource_id} missing runtime_relevance")
        try:
            rel_path = ensure_safe_relative_path(resource["path"])
        except (KeyError, ProvenanceError) as exc:
            errors.append(str(exc))
            continue
        try:
            disk_path = require_regular_file(root, rel_path)
        except ProvenanceError as exc:
            errors.append(str(exc))
            continue
        actual_hash = sha256_file(disk_path)
        expected_hash = resource.get("sha256")
        if actual_hash != expected_hash:
            errors.append(
                f"changed vendored resource {resource_id}: sha256 "
                f"{expected_hash} -> {actual_hash}"
            )
        if isinstance(resource_id, str) and resource_id:
            by_id[resource_id] = resource
    return errors, by_id


def validate_embedded_inventories(
    lock: dict[str, Any],
    locked_pins: dict[str, dict[str, Any]],
) -> tuple[list[str], list[str]]:
    inventories, errors = validate_object_list(
        lock.get("embedded_inventories"),
        "embedded_inventories",
        "owner_identity",
    )
    referenced_files: list[str] = []
    if not inventories:
        errors.append("embedded_inventories must contain at least one inventory")
        return errors, referenced_files
    owner_identities = {inventory["owner_identity"] for inventory in inventories}
    if owner_identities != set(EXPECTED_EMBEDDED_INVENTORY_DIGESTS):
        missing = sorted(set(EXPECTED_EMBEDDED_INVENTORY_DIGESTS) - owner_identities)
        extra = sorted(owner_identities - set(EXPECTED_EMBEDDED_INVENTORY_DIGESTS))
        if missing:
            errors.append(f"missing embedded inventories: {', '.join(missing)}")
        if extra:
            errors.append(f"unexpected embedded inventories: {', '.join(extra)}")

    for inventory in inventories:
        owner_identity = inventory["owner_identity"]
        expected_inventory_digest = EXPECTED_EMBEDDED_INVENTORY_DIGESTS.get(
            owner_identity
        )
        inventory_digest = canonical_sha256(inventory)
        if inventory_digest != expected_inventory_digest:
            errors.append(
                f"embedded inventory {owner_identity} digest "
                f"{expected_inventory_digest} -> {inventory_digest}"
            )
        owner_pin = locked_pins.get(owner_identity)
        if owner_pin is None:
            errors.append(f"embedded inventory owner pin not found: {owner_identity}")
            continue
        expected_owner_version = owner_pin["state"].get("version")
        if inventory.get("owner_version") != expected_owner_version:
            errors.append(
                f"embedded inventory {owner_identity} owner_version "
                f"{inventory.get('owner_version')} != {expected_owner_version}"
            )
        if not inventory.get("inventory_name"):
            errors.append(f"embedded inventory {owner_identity} missing inventory_name")
        source = inventory.get("inventory_source")
        owner_revision = owner_pin["state"].get("revision")
        if (
            not isinstance(source, str)
            or not source.startswith("https://raw.githubusercontent.com/")
            or owner_revision not in source
        ):
            errors.append(
                f"embedded inventory {owner_identity} inventory_source must be a pinned "
                "raw GitHub URL for the owner revision"
            )

        generated_notice_files, generated_notice_errors = validate_string_list(
            inventory.get("generated_notice_files"),
            f"embedded inventory {owner_identity} generated_notice_files",
        )
        errors.extend(generated_notice_errors)
        referenced_files.extend(generated_notice_files)

        components, component_errors = validate_object_list(
            inventory.get("components"),
            f"embedded inventory {owner_identity} components",
            "name",
        )
        errors.extend(component_errors)
        if not components:
            errors.append(
                f"embedded inventory {owner_identity} must contain at least one component"
            )
        for component in components:
            name = component["name"]
            for field_name in (
                "version",
                "resolved",
                "license_identifier",
                "license_source",
                "runtime_relevance",
            ):
                field_value = component.get(field_name)
                if not isinstance(field_value, str) or not field_value:
                    errors.append(f"embedded component {name} has invalid {field_name}")
            for url_field in ("resolved", "license_source"):
                url_value = component.get(url_field)
                if isinstance(url_value, str) and not url_value.startswith("https://"):
                    errors.append(f"embedded component {name} has invalid {url_field}")
            if component.get("scope") != "runtime":
                errors.append(
                    f"embedded component {name} has invalid scope {component.get('scope')}"
                )
            for field_name in ("license_files", "notice_files"):
                field_value, field_errors = validate_string_list(
                    component.get(field_name),
                    f"embedded component {name} {field_name}",
                )
                errors.extend(field_errors)
                referenced_files.extend(field_value)
    return errors, referenced_files


def validate_mermaid_inventory(
    root: Path,
    resource: dict[str, Any],
) -> tuple[list[str], dict[str, Any] | None, str | None]:
    closure = resource.get("third_party_closure")
    if not isinstance(closure, dict):
        return (
            [f"vendored resource {resource.get('id')} missing third_party_closure"],
            None,
            None,
        )

    errors = validate_key_order(
        closure,
        f"vendored resource {resource.get('id')} third_party_closure",
        EXPECTED_MERMAID_CLOSURE_KEYS,
    )
    inventory_path_raw = closure.get("inventory_path")
    report_path_raw = closure.get("report_path")
    inventory_path: PurePosixPath | None = None
    report_path: PurePosixPath | None = None
    try:
        inventory_path = ensure_safe_relative_path(
            inventory_path_raw,
            prefix=INVENTORIES_DIR,
        )
    except ProvenanceError as exc:
        errors.append(str(exc))
    try:
        report_path = ensure_safe_relative_path(
            report_path_raw,
            prefix=PurePosixPath("ThirdParty/Licenses/mermaid"),
        )
    except ProvenanceError as exc:
        errors.append(str(exc))

    if inventory_path is not None and inventory_path != MERMAID_INVENTORY_PATH:
        errors.append(
            f"vendored resource {resource.get('id')} inventory_path "
            f"{inventory_path} != {MERMAID_INVENTORY_PATH}"
        )
    if report_path is not None and report_path != MERMAID_REPORT_PATH:
        errors.append(
            f"vendored resource {resource.get('id')} report_path "
            f"{report_path} != {MERMAID_REPORT_PATH}"
        )
    for field_name in ("inventory_sha256", "report_sha256", "policy_sha256"):
        errors.extend(
            validate_sha256_string(
                closure.get(field_name),
                f"vendored resource {resource.get('id')} third_party_closure.{field_name}",
            )
        )
    expected_closure_hashes = {
        "inventory_sha256": EXPECTED_MERMAID_INVENTORY_SHA256,
        "report_sha256": EXPECTED_MERMAID_REPORT_SHA256,
        "policy_sha256": EXPECTED_MERMAID_POLICY_SHA256,
    }
    for field_name, expected_hash in expected_closure_hashes.items():
        if closure.get(field_name) != expected_hash:
            errors.append(
                f"vendored resource {resource.get('id')} "
                f"third_party_closure.{field_name} "
                f"{closure.get(field_name)} != {expected_hash}"
            )

    inventory: dict[str, Any] | None = None
    if inventory_path is not None:
        try:
            inventory_disk_path = require_regular_file(root, inventory_path)
        except ProvenanceError as exc:
            errors.append(str(exc))
        else:
            actual_hash = sha256_file(inventory_disk_path)
            expected_hash = closure.get("inventory_sha256")
            if actual_hash != expected_hash:
                errors.append(
                    f"changed Mermaid inventory: sha256 {expected_hash} -> {actual_hash}"
                )
            loaded_inventory = load_json(inventory_disk_path)
            if not isinstance(loaded_inventory, dict):
                raise ProvenanceError("Mermaid inventory must be a json object")
            inventory = loaded_inventory
            errors.extend(validate_mermaid_inventory_object(inventory))
            expected_policy = canonical_sha256(inventory)
            if closure.get("policy_sha256") != expected_policy:
                errors.append(
                    f"Mermaid policy anchor {closure.get('policy_sha256')} -> "
                    f"{expected_policy}"
                )

    if report_path is not None:
        try:
            report_disk_path = require_regular_file(root, report_path)
        except ProvenanceError as exc:
            errors.append(str(exc))
        else:
            actual_hash = sha256_file(report_disk_path)
            expected_hash = closure.get("report_sha256")
            if actual_hash != expected_hash:
                errors.append(
                    f"changed Mermaid report: sha256 {expected_hash} -> {actual_hash}"
                )
            if inventory is not None:
                errors.extend(validate_mermaid_report(report_disk_path, inventory))

    return errors, inventory, str(inventory_path) if inventory_path is not None else None


def validate_mermaid_inventory_object(inventory: dict[str, Any]) -> list[str]:
    errors = validate_key_order(
        inventory,
        "Mermaid inventory",
        EXPECTED_MERMAID_INVENTORY_KEYS,
    )
    if inventory.get("schema_version") != 1:
        errors.append(
            f"Mermaid inventory.schema_version {inventory.get('schema_version')} != 1"
        )
    if inventory.get("resource_id") != EXPECTED_VENDORED_RESOURCE["id"]:
        errors.append("Mermaid inventory.resource_id changed")
    if inventory.get("resource_path") != EXPECTED_VENDORED_RESOURCE["path"]:
        errors.append("Mermaid inventory.resource_path changed")
    if inventory.get("project") != "mermaid":
        errors.append("Mermaid inventory.project changed")
    if inventory.get("version") != "10.9.5":
        errors.append("Mermaid inventory.version changed")
    if inventory.get("tag") != "v10.9.5":
        errors.append("Mermaid inventory.tag changed")
    if inventory.get("commit") != "665b3d05cbe1ac7b78b154a464de39c5d17ba7b9":
        errors.append("Mermaid inventory.commit changed")
    if inventory.get("package_manager") != "pnpm@8.15.4":
        errors.append("Mermaid inventory.package_manager changed")
    if not inventory.get("inventory_basis"):
        errors.append("Mermaid inventory.inventory_basis missing")

    errors.extend(
        validate_exact_object(
            inventory.get("authoritative_inputs"),
            "Mermaid inventory.authoritative_inputs",
            EXPECTED_MERMAID_AUTHORITATIVE_INPUTS,
        )
    )
    errors.extend(
        validate_exact_object(
            inventory.get("rebuild_verification"),
            "Mermaid inventory.rebuild_verification",
            EXPECTED_MERMAID_REBUILD_VERIFICATION,
        )
    )
    errors.extend(
        validate_exact_object(
            inventory.get("counts"),
            "Mermaid inventory.counts",
            EXPECTED_MERMAID_COUNTS,
        )
    )
    errors.extend(
        validate_exact_object(
            inventory.get("license_category_totals"),
            "Mermaid inventory.license_category_totals",
            EXPECTED_MERMAID_LICENSE_TOTALS,
        )
    )
    errors.extend(
        validate_exact_object(
            inventory.get("excluded_non_bundled_summary"),
            "Mermaid inventory.excluded_non_bundled_summary",
            EXPECTED_MERMAID_EXCLUDED_SUMMARY,
        )
    )

    packages, package_errors = validate_object_list(
        inventory.get("bundled_packages"),
        "Mermaid inventory bundled_packages",
        "id",
    )
    errors.extend(package_errors)
    if len(packages) != EXPECTED_MERMAID_COUNTS["bundled_package_instances"]:
        errors.append(
            "Mermaid inventory bundled_packages count "
            f"{len(packages)} != {EXPECTED_MERMAID_COUNTS['bundled_package_instances']}"
        )

    license_counts: Counter[str] = Counter()
    direct_count = 0
    transitive_count = 0
    prebundle_count = 0
    patched_count = 0
    redistribution_count = 0

    for package in packages:
        package_id = package["id"]
        errors.extend(
            validate_key_order(
                package,
                f"Mermaid package {package_id}",
                EXPECTED_MERMAID_PACKAGE_KEYS,
            )
        )
        name = package.get("name")
        version = package.get("version")
        if not isinstance(name, str) or not name:
            errors.append(f"Mermaid package {package_id} has invalid name")
        if not isinstance(version, str) or not version:
            errors.append(f"Mermaid package {package_id} has invalid version")
        elif package_id != f"{name}@{version}":
            errors.append(f"Mermaid package {package_id} id does not match name/version")

        resolved = package.get("resolved")
        if not isinstance(resolved, str) or not resolved.startswith("https://"):
            errors.append(f"Mermaid package {package_id} has invalid resolved")
        integrity = package.get("integrity")
        if not isinstance(integrity, str) or not integrity:
            errors.append(f"Mermaid package {package_id} has invalid integrity")

        dependency = package.get("dependency")
        if dependency not in ALLOWED_MERMAID_DEPENDENCIES:
            errors.append(
                f"Mermaid package {package_id} has invalid dependency {dependency}"
            )
        elif dependency == "direct":
            direct_count += 1
        else:
            transitive_count += 1

        parents, parent_errors = validate_string_list(
            package.get("parents"),
            f"Mermaid package {package_id} parents",
        )
        errors.extend(parent_errors)
        if not parents:
            errors.append(f"Mermaid package {package_id} must list at least one parent")

        license_identifier = package.get("license_identifier")
        if not isinstance(license_identifier, str) or not license_identifier:
            errors.append(f"Mermaid package {package_id} has invalid license_identifier")
        elif license_identifier == "UNKNOWN":
            errors.append(f"Mermaid package {package_id} may not use UNKNOWN license")
        else:
            license_counts[license_identifier] += 1

        redistribution_choice = package.get("redistribution_license_choice")
        if redistribution_choice is None:
            pass
        elif redistribution_choice != "Apache-2.0":
            errors.append(
                f"Mermaid package {package_id} has invalid "
                f"redistribution_license_choice {redistribution_choice}"
            )
        elif license_identifier != "(MPL-2.0 OR Apache-2.0)":
            errors.append(
                f"Mermaid package {package_id} may only select Apache-2.0 when "
                "dual-licensed under (MPL-2.0 OR Apache-2.0)"
            )
        else:
            redistribution_count += 1

        license_evidence = package.get("license_evidence")
        errors.extend(
            validate_key_order(
                license_evidence,
                f"Mermaid package {package_id} license_evidence",
                EXPECTED_MERMAID_LICENSE_EVIDENCE_KEYS,
            )
        )
        if isinstance(license_evidence, dict):
            source_kind = license_evidence.get("source_kind")
            if source_kind not in ALLOWED_MERMAID_LICENSE_EVIDENCE_KINDS:
                errors.append(
                    f"Mermaid package {package_id} has invalid "
                    f"license_evidence.source_kind {source_kind}"
                )
            for field_name in (
                "metadata_license_identifier",
                "inferred_license_identifier",
            ):
                field_value = license_evidence.get(field_name)
                if field_value is not None and (
                    not isinstance(field_value, str) or not field_value
                ):
                    errors.append(
                        f"Mermaid package {package_id} has invalid "
                        f"license_evidence.{field_name}"
                    )
            metadata_license = license_evidence.get("metadata_license_identifier")
            inferred_license = license_evidence.get("inferred_license_identifier")
        else:
            source_kind = None
            metadata_license = None
            inferred_license = None

        source_names, source_name_errors = validate_string_list(
            package.get("license_notice_source_names"),
            f"Mermaid package {package_id} license_notice_source_names",
        )
        errors.extend(source_name_errors)
        for source_name in source_names:
            if "/" in source_name or "\\" in source_name:
                errors.append(
                    f"Mermaid package {package_id} source name must not contain "
                    f"path separators: {source_name}"
                )
        if source_kind == "package-json-license":
            if source_names:
                errors.append(
                    f"Mermaid package {package_id} package-json-license may not list "
                    "license_notice_source_names"
                )
            if metadata_license != license_identifier:
                errors.append(
                    f"Mermaid package {package_id} metadata license "
                    f"{metadata_license} != {license_identifier}"
                )
            if inferred_license is not None:
                errors.append(
                    f"Mermaid package {package_id} package-json-license may not set "
                    "inferred_license_identifier"
                )
        elif source_kind == "package-license-file" and not source_names:
            errors.append(
                f"Mermaid package {package_id} package-license-file must list "
                "license_notice_source_names"
            )

        patched = package.get("patched")
        if not isinstance(patched, bool):
            errors.append(f"Mermaid package {package_id} has invalid patched flag")
        elif patched:
            patched_count += 1
        patch_file = package.get("patch_file")
        if patched:
            try:
                ensure_safe_relative_path(patch_file)
            except ProvenanceError as exc:
                errors.append(str(exc))
        elif patch_file is not None:
            errors.append(
                f"Mermaid package {package_id} patch_file must be null when unpatched"
            )

        bundle_presence = package.get("bundle_presence")
        errors.extend(
            validate_key_order(
                bundle_presence,
                f"Mermaid package {package_id} bundle_presence",
                EXPECTED_MERMAID_BUNDLE_PRESENCE_KEYS,
            )
        )
        if isinstance(bundle_presence, dict):
            if bundle_presence.get("classification") != "bundled":
                errors.append(
                    f"Mermaid package {package_id} bundle_presence.classification "
                    f"{bundle_presence.get('classification')} != bundled"
                )
            mode = bundle_presence.get("mode")
            if mode not in ALLOWED_MERMAID_BUNDLE_MODES:
                errors.append(
                    f"Mermaid package {package_id} has invalid bundle mode {mode}"
                )
            elif mode == "embedded-prebundle":
                prebundle_count += 1

        bundle_reason = package.get("bundle_reason")
        if not isinstance(bundle_reason, str) or not bundle_reason:
            errors.append(f"Mermaid package {package_id} has invalid bundle_reason")
        bundle_evidence, bundle_evidence_errors = validate_string_list(
            package.get("bundle_evidence"),
            f"Mermaid package {package_id} bundle_evidence",
        )
        errors.extend(bundle_evidence_errors)
        if not bundle_evidence:
            errors.append(
                f"Mermaid package {package_id} must include bundle_evidence"
            )

    if dict(license_counts) != EXPECTED_MERMAID_LICENSE_TOTALS:
        errors.append(
            "Mermaid inventory license totals "
            f"{dict(license_counts)} != {EXPECTED_MERMAID_LICENSE_TOTALS}"
        )
    if direct_count != EXPECTED_MERMAID_COUNTS["bundled_direct_dependencies"]:
        errors.append(
            f"Mermaid inventory direct bundled count {direct_count} != "
            f"{EXPECTED_MERMAID_COUNTS['bundled_direct_dependencies']}"
        )
    if transitive_count != EXPECTED_MERMAID_COUNTS["bundled_transitive_dependencies"]:
        errors.append(
            f"Mermaid inventory transitive bundled count {transitive_count} != "
            f"{EXPECTED_MERMAID_COUNTS['bundled_transitive_dependencies']}"
        )
    if prebundle_count != EXPECTED_MERMAID_COUNTS["bundled_prebundle_packages"]:
        errors.append(
            f"Mermaid inventory prebundle count {prebundle_count} != "
            f"{EXPECTED_MERMAID_COUNTS['bundled_prebundle_packages']}"
        )
    if patched_count != EXPECTED_MERMAID_COUNTS["patched_bundled_packages"]:
        errors.append(
            f"Mermaid inventory patched bundled count {patched_count} != "
            f"{EXPECTED_MERMAID_COUNTS['patched_bundled_packages']}"
        )
    if redistribution_count != 1:
        errors.append(
            "Mermaid inventory redistribution license selection count "
            f"{redistribution_count} != 1"
        )
    return errors


def validate_mermaid_report(report_path: Path, inventory: dict[str, Any]) -> list[str]:
    try:
        report_text = report_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise ProvenanceError(f"could not read file: {report_path}: {exc}") from exc

    errors: list[str] = []
    for snippet in (
        "# Mermaid 10.9.5 bundled third-party license report",
        str(MERMAID_INVENTORY_PATH),
        "## Package inventory",
        "## Exact license text groups for the 62-package inventory",
        "## Auxiliary preserved upstream-emitted notice outside the 62-package inventory",
        "js-yaml 4.1.0",
        "block 2 preserves the upstream-emitted",
    ):
        if snippet not in report_text:
            errors.append(f"Mermaid report missing snippet: {snippet}")

    lines = report_text.splitlines()
    in_package_section = False
    report_rows: list[str] = []
    for line in lines:
        if line == "## Package inventory":
            in_package_section = True
            continue
        if in_package_section and line.startswith("## "):
            break
        if not in_package_section:
            continue
        match = MERMAID_REPORT_ROW.match(line)
        if match:
            report_rows.append(match.group(1))

    coverage_rows: dict[str, tuple[str, str, str]] = {}
    for line in lines:
        match = MERMAID_REPORT_COVERAGE_ROW.match(line)
        if not match:
            continue
        package_id = match.group(1)
        if package_id in coverage_rows:
            errors.append(f"Mermaid report has duplicate license coverage for {package_id}")
        coverage_rows[package_id] = (
            match.group(2),
            match.group(3),
            match.group(4),
        )

    packages = [
        package
        for package in inventory.get("bundled_packages", [])
        if isinstance(package, dict) and isinstance(package.get("id"), str)
    ]
    expected_rows = [package["id"] for package in packages]
    if report_rows != expected_rows:
        errors.append("Mermaid report package inventory table does not match inventory ids")
    if sorted(coverage_rows) != sorted(expected_rows):
        errors.append("Mermaid report license coverage groups do not match inventory ids")
    for package in packages:
        package_id = package["id"]
        coverage = coverage_rows.get(package_id)
        if coverage is None:
            continue
        source, license_kind, license_identifier = coverage
        source_names = package.get("license_notice_source_names", [])
        expected_sources = {
            f"{package.get('resolved')}#package/{source_name.split('#', 1)[0]}"
            for source_name in source_names
            if isinstance(source_name, str)
        }
        evidence = package.get("license_evidence")
        if (
            isinstance(evidence, dict)
            and evidence.get("source_kind") == "package-json-license"
        ):
            expected_sources.add(f"{package.get('resolved')}#package/package.json")
        if source not in expected_sources:
            errors.append(
                f"Mermaid report license source for {package_id} "
                f"{source} not in inventory sources"
            )
        if not isinstance(evidence, dict):
            continue
        metadata_license = evidence.get("metadata_license_identifier")
        inferred_license = evidence.get("inferred_license_identifier")
        expected_kind = "metadata" if isinstance(metadata_license, str) else "inferred"
        expected_license = (
            metadata_license if isinstance(metadata_license, str) else inferred_license
        )
        if license_kind != expected_kind or license_identifier != expected_license:
            errors.append(
                f"Mermaid report license evidence for {package_id} "
                f"{license_kind} {license_identifier} != "
                f"{expected_kind} {expected_license}"
            )
    return errors


def collect_package_file_references(lock: dict[str, Any]) -> list[str]:
    refs: list[str] = []
    pins = lock["package_resolved"]["pins"]
    for pin in pins:
        refs.extend(item for item in pin.get("license_files", []) if isinstance(item, str))
        refs.extend(item for item in pin.get("notice_files", []) if isinstance(item, str))
    for resource in lock["vendored_resources"]:
        refs.extend(
            item for item in resource.get("license_files", []) if isinstance(item, str)
        )
        refs.extend(
            item for item in resource.get("notice_files", []) if isinstance(item, str)
        )
    return refs


def collect_inventory_references(lock: dict[str, Any]) -> list[str]:
    refs: list[str] = []
    for resource in lock["vendored_resources"]:
        closure = resource.get("third_party_closure")
        if not isinstance(closure, dict):
            continue
        inventory_path = closure.get("inventory_path")
        if isinstance(inventory_path, str):
            refs.append(inventory_path)
    return refs


def validate_project_license(root: Path, lock: dict[str, Any]) -> list[str]:
    metadata = lock.get("project_license")
    if not isinstance(metadata, dict):
        raise ProvenanceError("project_license must be an object")
    errors = validate_key_order(
        metadata,
        "project_license",
        ["copyright", "license_identifier", "path", "sha256"],
    )
    if metadata.get("path") != str(PROJECT_LICENSE_PATH):
        errors.append(
            f"project_license.path must be {PROJECT_LICENSE_PATH}, found {metadata.get('path')}"
        )
    if metadata.get("license_identifier") != "MIT":
        errors.append(
            f"project_license.license_identifier must be MIT, found "
            f"{metadata.get('license_identifier')}"
        )
    if metadata.get("copyright") != "Copyright (c) 2026 AnYuan":
        errors.append("project_license.copyright changed")
    expected_hash = metadata.get("sha256")
    if (
        not isinstance(expected_hash, str)
        or len(expected_hash) != 64
        or any(character not in "0123456789abcdef" for character in expected_hash)
    ):
        errors.append("project_license.sha256 is invalid")
        return errors
    if expected_hash != EXPECTED_PROJECT_LICENSE_SHA256:
        errors.append(
            f"project_license.sha256 {expected_hash} != "
            f"{EXPECTED_PROJECT_LICENSE_SHA256}"
        )
    license_path = require_regular_file(root, PROJECT_LICENSE_PATH)
    actual_hash = sha256_file(license_path)
    if actual_hash != expected_hash:
        errors.append(
            f"changed project license: sha256 {expected_hash} -> {actual_hash}"
        )
    return errors


def validate_package_manifest(root: Path, lock: dict[str, Any]) -> list[str]:
    section = lock.get("package_resolved")
    if not isinstance(section, dict):
        raise ProvenanceError("package_resolved must be an object")
    locked_hash = section.get("origin_hash")
    errors = validate_sha256_string(
        locked_hash,
        "package_resolved.origin_hash",
    )
    if locked_hash != EXPECTED_PACKAGE_MANIFEST_SHA256:
        errors.append(
            f"package_resolved.origin_hash {locked_hash} != "
            f"{EXPECTED_PACKAGE_MANIFEST_SHA256}"
        )
    manifest_path = require_regular_file(root, PACKAGE_MANIFEST_PATH)
    actual_hash = sha256_file(manifest_path)
    if actual_hash != locked_hash:
        errors.append(
            f"changed package manifest: sha256 {locked_hash} -> {actual_hash}"
        )
    return errors


def validate_fixed_file(
    root: Path,
    lock: dict[str, Any],
    metadata_key: str,
    expected_path: PurePosixPath,
    expected_hash: str,
) -> list[str]:
    metadata = lock.get(metadata_key)
    if not isinstance(metadata, dict):
        raise ProvenanceError(f"{metadata_key} must be an object")
    errors = validate_key_order(
        metadata,
        metadata_key,
        ["path", "sha256"],
    )
    if metadata.get("path") != str(expected_path):
        errors.append(
            f"{metadata_key}.path must be {expected_path}, found {metadata.get('path')}"
        )
    locked_hash = metadata.get("sha256")
    errors.extend(validate_sha256_string(locked_hash, f"{metadata_key}.sha256"))
    if locked_hash != expected_hash:
        errors.append(
            f"{metadata_key}.sha256 {locked_hash} != {expected_hash}"
        )
    file_path = require_regular_file(root, expected_path)
    actual_hash = sha256_file(file_path)
    if actual_hash != locked_hash:
        errors.append(
            f"changed {metadata_key}: sha256 {locked_hash} -> {actual_hash}"
        )
    return errors


def validate_notice_coverage(
    root: Path,
    lock: dict[str, Any],
    mermaid_inventory: dict[str, Any] | None,
) -> list[str]:
    notice_path = require_regular_file(root, NOTICE_PATH)
    try:
        notice_text = notice_path.read_text(encoding="utf-8").casefold()
    except (OSError, UnicodeDecodeError) as exc:
        raise ProvenanceError(f"could not read file: {NOTICE_PATH}: {exc}") from exc

    tokens: set[str] = {
        str(PROJECT_LICENSE_PATH),
        str(LOCK_PATH),
    }
    try:
        for pin in lock["package_resolved"]["pins"]:
            tokens.update(
                {
                    pin["identity"],
                    pin["location"],
                    pin["license_identifier"],
                }
            )
            tokens.update(pin["state"].values())
            tokens.update(pin.get("license_files", []))
            tokens.update(pin.get("notice_files", []))
        for resource in lock["vendored_resources"]:
            tokens.update(
                {
                    resource["path"],
                    resource["version"],
                    resource["source_url"],
                    resource["sha256"],
                    resource["license_identifier"],
                }
            )
            tokens.update(resource.get("license_files", []))
            tokens.update(resource.get("notice_files", []))
            closure = resource.get("third_party_closure")
            if isinstance(closure, dict):
                inventory_path = closure.get("inventory_path")
                report_path = closure.get("report_path")
                if isinstance(inventory_path, str):
                    tokens.add(inventory_path)
                if isinstance(report_path, str):
                    tokens.add(report_path)
        for inventory in lock["embedded_inventories"]:
            tokens.update(
                {
                    inventory["owner_identity"],
                    inventory["owner_version"],
                    inventory["inventory_source"],
                }
            )
            tokens.update(inventory.get("generated_notice_files", []))
            for component in inventory["components"]:
                tokens.update(
                    {
                        component["name"],
                        component["resolved"],
                        component["license_identifier"],
                    }
                )
                tokens.update(component.get("license_files", []))
                tokens.update(component.get("notice_files", []))
    except (KeyError, TypeError, AttributeError) as exc:
        raise ProvenanceError(f"invalid metadata for third-party notice coverage: {exc}") from exc

    errors: list[str] = []
    if any(not isinstance(token, str) for token in tokens):
        raise ProvenanceError("third-party notice coverage metadata must contain strings")
    for token in sorted(tokens, key=str.casefold):
        if token.casefold() not in notice_text:
            errors.append(f"third-party notices missing provenance token: {token}")

    if mermaid_inventory is not None:
        counts = mermaid_inventory["counts"]
        totals = mermaid_inventory["license_category_totals"]
        snippets = [
            mermaid_inventory["tag"],
            mermaid_inventory["commit"],
            "62 bundled package instances",
            (
                f"{counts['bundled_direct_dependencies']} direct + "
                f"{counts['bundled_transitive_dependencies']} transitive bundled instances"
            ),
            (
                f"{counts['bundled_prebundle_packages']} bundled via prebuilt sub-bundles"
            ),
            (
                f"{counts['excluded_non_bundled_packages']} production-closure "
                "packages excluded as non-bundled"
            ),
            "complete dependency closure.",
        ]
        for license_identifier, count in totals.items():
            snippets.append(f"| {license_identifier} | {count} |")
        for snippet in snippets:
            if snippet.casefold() not in notice_text:
                errors.append(
                    f"third-party notices missing Mermaid summary snippet: {snippet}"
                )
    return errors


def verify(root: Path) -> list[str]:
    root = root.resolve()
    lock_path = require_regular_file(root, LOCK_PATH)
    lock = load_json(lock_path)
    if not isinstance(lock, dict):
        raise ProvenanceError("lock file must be a json object")
    if lock.get("schema_version") != 1:
        raise ProvenanceError(f"unsupported schema_version: {lock.get('schema_version')}")

    errors = validate_key_order(lock, "provenance lock", EXPECTED_LOCK_KEYS)
    errors.extend(validate_project_license(root, lock))
    errors.extend(validate_package_manifest(root, lock))
    errors.extend(
        validate_fixed_file(
            root,
            lock,
            "project_notice",
            NOTICE_PATH,
            EXPECTED_PROJECT_NOTICE_SHA256,
        )
    )
    errors.extend(
        validate_policy_anchor(
            lock.get("checked_in_files"),
            "checked_in_files",
            EXPECTED_CHECKED_IN_FILES_POLICY_SHA256,
        )
    )
    errors.extend(
        validate_policy_anchor(
            lock.get("package_resolved"),
            "package_resolved",
            EXPECTED_PACKAGE_PROVENANCE_POLICY_SHA256,
        )
    )
    checked_in_errors, checked_in_by_path = validate_checked_in_files(root, lock)
    errors.extend(checked_in_errors)
    disk_license_files, disk_inventory_errors = inventory_regular_files(
        root,
        PurePosixPath("ThirdParty/Licenses"),
    )
    errors.extend(disk_inventory_errors)
    for unlisted in sorted(disk_license_files - set(checked_in_by_path)):
        errors.append(f"unlisted checked-in license/notice file: {unlisted}")
    for missing in sorted(set(checked_in_by_path) - disk_license_files):
        errors.append(f"listed license/notice file missing from disk inventory: {missing}")
    package_errors, locked_pins = validate_package_resolved(root, lock)
    errors.extend(package_errors)
    vendored_errors, vendored_resources = validate_vendored_resources(root, lock)
    errors.extend(vendored_errors)
    mermaid_inventory: dict[str, Any] | None = None
    mermaid_inventory_path: str | None = None
    mermaid_resource = vendored_resources.get("mermaid-dist")
    if mermaid_resource is None:
        errors.append("missing vendored resource mermaid-dist")
    else:
        mermaid_errors, mermaid_inventory, mermaid_inventory_path = (
            validate_mermaid_inventory(root, mermaid_resource)
        )
        errors.extend(mermaid_errors)
    embedded_errors, embedded_refs = validate_embedded_inventories(lock, locked_pins)
    errors.extend(embedded_errors)

    try:
        lock_file_refs = collect_package_file_references(lock)
        inventory_refs = collect_inventory_references(lock)
    except (KeyError, TypeError, AttributeError) as exc:
        raise ProvenanceError(f"missing lock section: {exc}") from exc
    all_refs = sorted(set(lock_file_refs + embedded_refs))
    for ref in all_refs:
        try:
            ensure_safe_relative_path(
                ref,
                prefix=PurePosixPath("ThirdParty/Licenses"),
            )
        except ProvenanceError as exc:
            errors.append(str(exc))
            continue
        if ref not in checked_in_by_path:
            errors.append(f"referenced file missing from checked_in_files: {ref}")

    orphan_files = sorted(set(checked_in_by_path) - set(all_refs))
    for orphan in orphan_files:
        errors.append(f"orphan checked-in file not referenced by provenance metadata: {orphan}")

    disk_inventory_files, inventory_dir_errors = inventory_regular_files(
        root,
        INVENTORIES_DIR,
    )
    errors.extend(inventory_dir_errors)
    expected_inventory_refs = sorted(set(inventory_refs))
    if mermaid_inventory_path is not None and mermaid_inventory_path not in expected_inventory_refs:
        expected_inventory_refs.append(mermaid_inventory_path)
        expected_inventory_refs.sort()
    for unlisted in sorted(disk_inventory_files - set(expected_inventory_refs)):
        errors.append(f"unlisted checked-in inventory file: {unlisted}")
    for missing in sorted(set(expected_inventory_refs) - disk_inventory_files):
        errors.append(f"listed inventory file missing from disk inventory: {missing}")

    errors.extend(validate_notice_coverage(root, lock, mermaid_inventory))
    return errors


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Verify third-party provenance metadata.")
    parser.add_argument(
        "--root",
        default=".",
        help="repository root to verify (default: current directory)",
    )
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    try:
        errors = verify(root)
    except ProvenanceError as exc:
        print(f"FAIL provenance: {exc}", file=sys.stderr)
        return 1

    if errors:
        for error in errors:
            print(f"FAIL provenance: {error}", file=sys.stderr)
        print(f"FAIL provenance: {len(errors)} issue(s) found.", file=sys.stderr)
        return 1

    print(
        "PASS provenance: package manifest/resolution, legal files, vendored "
        "assets, and notices match ThirdParty/provenance.lock.json"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
