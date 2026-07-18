#!/usr/bin/env python3
"""Normalize and compare MarkdownKit public Swift symbol graphs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1
SYNTHESIZED_MARKER = "::SYNTHESIZED::"
ROLE_RELATIONSHIPS = {
    "requirementOf": "requirement",
    "defaultImplementationOf": "defaultImplementation",
}
PLATFORM_CONFIGS = {
    "macos": {
        "environment": "native",
        "minimumDeployment": "26.0",
        "name": "macos",
    },
    "ios-simulator": {
        "environment": "simulator",
        "minimumDeployment": "17.0",
        "name": "ios",
    },
}


class BaselineError(Exception):
    """A concise, user-actionable public API baseline failure."""


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def compact_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def json_object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise BaselineError(f"duplicate JSON object key '{key}'")
        result[key] = value
    return result


def read_json(path: Path, label: str) -> tuple[Any, str]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise BaselineError(f"cannot read {label} '{path}': {error}") from error
    try:
        return json.loads(text, object_pairs_hook=json_object_pairs), text
    except (json.JSONDecodeError, UnicodeDecodeError, BaselineError) as error:
        raise BaselineError(f"malformed {label} '{path}': {error}") from error


def require_mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise BaselineError(f"{label} must be an object")
    return value


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise BaselineError(f"{label} must be a non-empty string")
    return value


def require_text(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise BaselineError(f"{label} must be a string")
    return value


def normalize_value(value: Any, label: str) -> Any:
    if value is None or isinstance(value, (bool, int, str)):
        return value
    if isinstance(value, list):
        return [normalize_value(item, label) for item in value]
    if isinstance(value, dict):
        return {
            key: normalize_value(value[key], label)
            for key in sorted(value)
            if isinstance(key, str)
        }
    raise BaselineError(f"{label} contains unsupported JSON data")


def normalize_availability(value: Any, label: str) -> Any:
    normalized = normalize_value(value, label)
    if isinstance(normalized, list):
        return sorted(normalized, key=compact_json)
    return normalized


def normalize_version(value: Any, label: str) -> str:
    version = require_mapping(value, label)
    major = version.get("major")
    minor = version.get("minor", 0)
    patch = version.get("patch", 0)
    if not all(isinstance(part, int) and part >= 0 for part in (major, minor, patch)):
        raise BaselineError(f"{label} must contain non-negative integer version components")
    if patch:
        return f"{major}.{minor}.{patch}"
    return f"{major}.{minor}"


def normalized_graph_platform(graph: dict[str, Any], label: str) -> dict[str, str]:
    module = require_mapping(graph.get("module"), f"{label}.module")
    platform = require_mapping(module.get("platform"), f"{label}.module.platform")
    operating_system = require_mapping(
        platform.get("operatingSystem"), f"{label}.module.platform.operatingSystem"
    )
    raw_name = require_string(
        operating_system.get("name"), f"{label}.module.platform.operatingSystem.name"
    ).lower()
    name = {"macosx": "macos"}.get(raw_name, raw_name)
    environment = platform.get("environment", "native")
    if not isinstance(environment, str) or not environment:
        raise BaselineError(f"{label}.module.platform.environment must be a non-empty string")
    return {
        "environment": environment,
        "minimumDeployment": normalize_version(
            operating_system.get("minimumVersion"),
            f"{label}.module.platform.operatingSystem.minimumVersion",
        ),
        "name": name,
    }


def graph_records(graph: dict[str, Any], label: str) -> list[dict[str, Any]]:
    symbols = graph.get("symbols")
    if isinstance(symbols, list):
        records = symbols
    elif isinstance(symbols, dict):
        records = list(symbols.values())
    else:
        raise BaselineError(f"{label}.symbols must be an array or object")
    result: list[dict[str, Any]] = []
    for index, symbol in enumerate(records):
        result.append(require_mapping(symbol, f"{label}.symbols[{index}]"))
    return result


def graph_relationships(graph: dict[str, Any], label: str) -> list[dict[str, Any]]:
    relationships = graph.get("relationships")
    if not isinstance(relationships, list):
        raise BaselineError(f"{label}.relationships must be an array")
    return [
        require_mapping(relationship, f"{label}.relationships[{index}]")
        for index, relationship in enumerate(relationships)
    ]


def symbol_raw_id(symbol: dict[str, Any], label: str) -> str:
    identifier = require_mapping(symbol.get("identifier"), f"{label}.identifier")
    return require_string(identifier.get("precise"), f"{label}.identifier.precise")


def canonical_declaration(symbol: dict[str, Any], label: str) -> list[dict[str, str]]:
    fragments = symbol.get("declarationFragments")
    if not isinstance(fragments, list):
        raise BaselineError(f"{label}.declarationFragments must be an array")

    result: list[dict[str, str]] = []
    for index, fragment in enumerate(fragments):
        fragment_map = require_mapping(fragment, f"{label}.declarationFragments[{index}]")
        kind = require_string(fragment_map.get("kind"), f"{label}.declarationFragments[{index}].kind")
        spelling = require_text(
            fragment_map.get("spelling"), f"{label}.declarationFragments[{index}].spelling"
        )
        if kind == "text":
            spelling = re.sub(r"\s+", " ", spelling)
            if not spelling:
                continue
            if result and result[-1]["kind"] == "text":
                result[-1]["spelling"] = re.sub(
                    r"\s+",
                    " ",
                    result[-1]["spelling"] + spelling,
                )
                continue
        result.append({"kind": kind, "spelling": spelling})
    return result


def symbol_path(symbol: dict[str, Any], label: str) -> list[str]:
    path = symbol.get("pathComponents")
    if not isinstance(path, list) or not path:
        raise BaselineError(f"{label}.pathComponents must be a non-empty array")
    return [require_string(component, f"{label}.pathComponents") for component in path]


def symbol_extension(symbol: dict[str, Any], label: str) -> dict[str, Any] | None:
    extension = symbol.get("swiftExtension")
    if extension is None:
        return None
    extension_map = require_mapping(extension, f"{label}.swiftExtension")
    normalized = normalize_value(extension_map, f"{label}.swiftExtension")
    if "extendedModule" not in normalized:
        raise BaselineError(f"{label}.swiftExtension.extendedModule is required")
    require_string(normalized["extendedModule"], f"{label}.swiftExtension.extendedModule")
    return normalized


def identity_components(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "context": record["context"],
        "declaration": record["declaration"],
        "kind": record["kind"],
        "path": record["path"],
        "role": record["role"],
    }


def make_identity(record: dict[str, Any]) -> str:
    payload = compact_json(identity_components(record)).encode("utf-8")
    return f"sha256:{hashlib.sha256(payload).hexdigest()}"


def relationship_sort_key(relationship: dict[str, str]) -> str:
    return compact_json(relationship)


def normalize_graphs(
    input_dir: Path, module_name: str, platform_name: str
) -> dict[str, Any]:
    if not input_dir.is_dir():
        raise BaselineError(f"symbol graph input directory does not exist: '{input_dir}'")

    expected_platform = PLATFORM_CONFIGS[platform_name]
    name_pattern = re.compile(
        rf"^{re.escape(module_name)}(?:@[^/]+)?\.symbols\.json$"
    )
    graph_paths = sorted(input_dir.glob("*.symbols.json"))
    if not graph_paths:
        raise BaselineError(f"no symbol graph JSON files found in '{input_dir}'")
    unexpected = [path.name for path in graph_paths if not name_pattern.fullmatch(path.name)]
    if unexpected:
        raise BaselineError(
            "unexpected symbol graph file(s): " + ", ".join(unexpected)
        )

    base_path = input_dir / f"{module_name}.symbols.json"
    if base_path not in graph_paths:
        raise BaselineError(f"missing base symbol graph '{base_path.name}'")

    all_symbols: list[tuple[dict[str, Any], str]] = []
    all_relationships: list[tuple[dict[str, Any], str]] = []
    raw_ids: set[str] = set()
    raw_symbol_ids: set[str] = set()

    for path in graph_paths:
        graph, _ = read_json(path, "symbol graph")
        graph = require_mapping(graph, f"symbol graph '{path.name}'")
        graph_module = require_mapping(graph.get("module"), f"symbol graph '{path.name}'.module")
        actual_module = require_string(graph_module.get("name"), f"symbol graph '{path.name}'.module.name")
        if actual_module != module_name:
            raise BaselineError(
                f"wrong module in '{path.name}': expected '{module_name}', found '{actual_module}'"
            )
        actual_platform = normalized_graph_platform(graph, f"symbol graph '{path.name}'")
        if actual_platform != expected_platform:
            raise BaselineError(
                f"wrong platform in '{path.name}': expected {compact_json(expected_platform)}, "
                f"found {compact_json(actual_platform)}"
            )

        records = graph_records(graph, f"symbol graph '{path.name}'")
        if path == base_path and not records:
            raise BaselineError(f"base symbol graph '{path.name}' contains no symbols")
        for index, symbol in enumerate(records):
            label = f"symbol graph '{path.name}'.symbols[{index}]"
            raw_id = symbol_raw_id(symbol, label)
            if raw_id in raw_ids:
                raise BaselineError(f"duplicate raw symbol identifier '{raw_id}'")
            raw_ids.add(raw_id)
            raw_symbol_ids.add(raw_id)
            all_symbols.append((symbol, label))
        for index, relationship in enumerate(
            graph_relationships(graph, f"symbol graph '{path.name}'")
        ):
            all_relationships.append(
                (relationship, f"symbol graph '{path.name}'.relationships[{index}]")
            )

    retained_raw_ids = {
        symbol_raw_id(symbol, label)
        for symbol, label in all_symbols
        if SYNTHESIZED_MARKER not in symbol_raw_id(symbol, label)
    }
    if not retained_raw_ids:
        raise BaselineError("module symbol graphs contain no non-synthesized symbols")

    role_relationships: dict[str, set[str]] = defaultdict(set)
    for relationship, label in all_relationships:
        kind = require_string(relationship.get("kind"), f"{label}.kind")
        source = require_string(relationship.get("source"), f"{label}.source")
        if source not in raw_symbol_ids:
            raise BaselineError(f"{label}.source does not identify a module symbol")
        if kind in ROLE_RELATIONSHIPS and source in retained_raw_ids:
            role_relationships[source].add(ROLE_RELATIONSHIPS[kind])

    raw_to_record: dict[str, dict[str, Any]] = {}
    identities: set[str] = set()
    for symbol, label in all_symbols:
        raw_id = symbol_raw_id(symbol, label)
        if raw_id not in retained_raw_ids:
            continue
        roles = role_relationships.get(raw_id, set())
        if len(roles) > 1:
            raise BaselineError(f"{label} has ambiguous semantic roles: {', '.join(sorted(roles))}")
        extension = symbol_extension(symbol, label)
        context = (
            extension["extendedModule"] if extension is not None else module_name
        )
        kind = require_mapping(symbol.get("kind"), f"{label}.kind")
        record: dict[str, Any] = {
            "context": require_string(context, f"{label}.context"),
            "kind": require_string(kind.get("identifier"), f"{label}.kind.identifier"),
            "path": symbol_path(symbol, label),
            "role": next(iter(roles), "standard"),
            "declaration": canonical_declaration(symbol, label),
            "accessLevel": require_string(symbol.get("accessLevel"), f"{label}.accessLevel"),
            "availability": normalize_availability(
                symbol.get("availability", []), f"{label}.availability"
            ),
        }
        if extension is not None:
            record["extension"] = extension
        record["identity"] = make_identity(record)
        if record["identity"] in identities:
            raise BaselineError(f"identity collision for {describe_symbol(record)}")
        identities.add(record["identity"])
        raw_to_record[raw_id] = record

    relationships: list[dict[str, str]] = []
    relationship_keys: set[str] = set()
    for relationship, label in all_relationships:
        source_raw = require_string(relationship.get("source"), f"{label}.source")
        if source_raw not in retained_raw_ids:
            continue
        source_record = raw_to_record.get(source_raw)
        if source_record is None:
            raise BaselineError(f"{label}.source has no normalized symbol")
        result: dict[str, str] = {
            "kind": require_string(relationship.get("kind"), f"{label}.kind"),
            "source": source_record["identity"],
        }
        target_raw = require_string(relationship.get("target"), f"{label}.target")
        target_record = raw_to_record.get(target_raw)
        if target_record is not None:
            result["target"] = target_record["identity"]
        else:
            fallback = relationship.get("targetFallback")
            if not isinstance(fallback, str) or not fallback:
                if target_raw in raw_symbol_ids:
                    raise BaselineError(
                        f"{label}.target is an excluded synthesized symbol without targetFallback"
                    )
                raise BaselineError(f"{label}.target is external but has no targetFallback")
            result["targetFallback"] = fallback
        key = relationship_sort_key(result)
        if key in relationship_keys:
            # The extractor can emit a byte-for-byte duplicate conformance
            # relationship. It has no additional public API meaning.
            continue
        relationship_keys.add(key)
        relationships.append(result)

    symbols = sorted(raw_to_record.values(), key=lambda record: record["identity"])
    relationships.sort(key=relationship_sort_key)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "module": module_name,
        "platform": expected_platform,
        "symbolCount": len(symbols),
        "relationshipCount": len(relationships),
        "symbols": symbols,
        "relationships": relationships,
    }


def ensure_no_precise_identifiers(value: Any, label: str) -> None:
    if isinstance(value, dict):
        for key, nested in value.items():
            if key in {"precise", "preciseIdentifier"}:
                raise BaselineError(f"{label} must not persist raw precise identifiers")
            ensure_no_precise_identifiers(nested, label)
    elif isinstance(value, list):
        for nested in value:
            ensure_no_precise_identifiers(nested, label)


def validate_symbol_record(
    record: Any, index: int, module_name: str
) -> dict[str, Any]:
    symbol = require_mapping(record, f"baseline.symbols[{index}]")
    required = {
        "identity",
        "context",
        "kind",
        "path",
        "role",
        "declaration",
        "accessLevel",
        "availability",
    }
    allowed = required | {"extension"}
    if not required.issubset(symbol) or not set(symbol).issubset(allowed):
        raise BaselineError(f"baseline.symbols[{index}] has unexpected or missing fields")
    for key in ("identity", "context", "kind", "role", "accessLevel"):
        require_string(symbol.get(key), f"baseline.symbols[{index}].{key}")
    if symbol["role"] not in {"standard", *ROLE_RELATIONSHIPS.values()}:
        raise BaselineError(f"baseline.symbols[{index}].role is invalid")
    if not isinstance(symbol["path"], list) or not symbol["path"]:
        raise BaselineError(f"baseline.symbols[{index}].path must be a non-empty array")
    for component in symbol["path"]:
        require_string(component, f"baseline.symbols[{index}].path")
    if not isinstance(symbol["declaration"], list):
        raise BaselineError(f"baseline.symbols[{index}].declaration must be an array")
    for fragment_index, fragment in enumerate(symbol["declaration"]):
        fragment = require_mapping(
            fragment, f"baseline.symbols[{index}].declaration[{fragment_index}]"
        )
        if set(fragment) != {"kind", "spelling"}:
            raise BaselineError(
                f"baseline.symbols[{index}].declaration[{fragment_index}] must contain kind and spelling"
            )
        require_string(fragment.get("kind"), f"baseline.symbols[{index}].declaration[{fragment_index}].kind")
        require_text(
            fragment.get("spelling"), f"baseline.symbols[{index}].declaration[{fragment_index}].spelling"
        )
    if not isinstance(symbol["availability"], (list, dict)):
        raise BaselineError(f"baseline.symbols[{index}].availability must be an array or object")
    if symbol["availability"] != normalize_availability(
        symbol["availability"], f"baseline.symbols[{index}].availability"
    ):
        raise BaselineError(f"baseline.symbols[{index}].availability is not sorted")
    if "extension" in symbol:
        extension = require_mapping(symbol["extension"], f"baseline.symbols[{index}].extension")
        extension_module = require_string(
            extension.get("extendedModule"), f"baseline.symbols[{index}].extension.extendedModule"
        )
        if symbol["context"] != extension_module:
            raise BaselineError(f"baseline.symbols[{index}].context does not match extension metadata")
    elif symbol["context"] != module_name:
        raise BaselineError(
            f"baseline.symbols[{index}].context must be {module_name}"
        )
    expected_identity = make_identity(symbol)
    if symbol["identity"] != expected_identity:
        raise BaselineError(f"baseline.symbols[{index}].identity does not match its structure")
    return symbol


def validate_baseline(
    baseline_path: Path, module_name: str, platform_name: str
) -> dict[str, Any]:
    baseline, text = read_json(baseline_path, "baseline")
    baseline = require_mapping(baseline, "baseline")
    if text != canonical_json(baseline):
        raise BaselineError("baseline JSON is not canonical sorted JSON")

    required = {
        "schemaVersion",
        "module",
        "platform",
        "symbolCount",
        "relationshipCount",
        "symbols",
        "relationships",
    }
    if set(baseline) != required:
        raise BaselineError("baseline has unexpected or missing top-level fields")
    if baseline["schemaVersion"] != SCHEMA_VERSION:
        raise BaselineError(
            f"unsupported baseline schemaVersion {baseline['schemaVersion']!r}"
        )
    if baseline["module"] != module_name:
        raise BaselineError(
            f"baseline module is '{baseline['module']}', expected '{module_name}'"
        )
    if baseline["platform"] != PLATFORM_CONFIGS[platform_name]:
        raise BaselineError(
            f"baseline platform is {compact_json(baseline['platform'])}, expected "
            f"{compact_json(PLATFORM_CONFIGS[platform_name])}"
        )
    if not isinstance(baseline["symbols"], list) or not isinstance(baseline["relationships"], list):
        raise BaselineError("baseline symbols and relationships must be arrays")
    if baseline["symbolCount"] != len(baseline["symbols"]):
        raise BaselineError("baseline symbolCount does not match symbols")
    if baseline["relationshipCount"] != len(baseline["relationships"]):
        raise BaselineError("baseline relationshipCount does not match relationships")

    ensure_no_precise_identifiers(baseline, "baseline")
    symbols = [
        validate_symbol_record(record, index, module_name)
        for index, record in enumerate(baseline["symbols"])
    ]
    identities = [symbol["identity"] for symbol in symbols]
    if len(set(identities)) != len(identities):
        raise BaselineError("baseline symbols have duplicate identities")
    if identities != sorted(identities):
        raise BaselineError("baseline symbols are not sorted by identity")
    identity_set = set(identities)

    relationships: list[dict[str, str]] = []
    relationship_keys: set[str] = set()
    for index, relationship in enumerate(baseline["relationships"]):
        relationship = require_mapping(relationship, f"baseline.relationships[{index}]")
        if set(relationship) not in ({"kind", "source", "target"}, {"kind", "source", "targetFallback"}):
            raise BaselineError(f"baseline.relationships[{index}] has invalid fields")
        for key in ("kind", "source"):
            require_string(relationship.get(key), f"baseline.relationships[{index}].{key}")
        if relationship["source"] not in identity_set:
            raise BaselineError(f"baseline.relationships[{index}].source is not a normalized symbol")
        if "target" in relationship:
            require_string(relationship["target"], f"baseline.relationships[{index}].target")
            if relationship["target"] not in identity_set:
                raise BaselineError(
                    f"baseline.relationships[{index}].target is not a normalized symbol"
                )
        else:
            fallback = require_string(
                relationship.get("targetFallback"),
                f"baseline.relationships[{index}].targetFallback",
            )
            if fallback.startswith(("s:", "c:", "u:")):
                raise BaselineError(
                    f"baseline.relationships[{index}].targetFallback must not be an opaque identifier"
                )
        key = relationship_sort_key(relationship)
        if key in relationship_keys:
            raise BaselineError("baseline relationships have duplicates")
        relationship_keys.add(key)
        relationships.append(relationship)
    if [relationship_sort_key(item) for item in relationships] != sorted(relationship_keys):
        raise BaselineError("baseline relationships are not sorted")
    return baseline


def describe_symbol(symbol: dict[str, Any]) -> str:
    return (
        f"{symbol['context']} {symbol['kind']} "
        f"{'.'.join(symbol['path'])} [{symbol['role']}]"
    )


def changed_fields(expected: dict[str, Any], actual: dict[str, Any]) -> str:
    fields = [
        key
        for key in sorted(set(expected) | set(actual))
        if key != "identity" and expected.get(key) != actual.get(key)
    ]
    return ", ".join(fields)


def emit_diagnostics(label: str, entries: Iterable[str], limit: int = 20) -> None:
    entries = list(entries)
    for entry in entries[:limit]:
        print(f"{label}: {entry}", file=sys.stderr)
    if len(entries) > limit:
        print(f"{label}: ... {len(entries) - limit} more", file=sys.stderr)


def describe_relationship(
    relationship: dict[str, str], symbols: dict[str, dict[str, Any]]
) -> str:
    source = symbols.get(relationship["source"])
    source_text = describe_symbol(source) if source else relationship["source"]
    if "target" in relationship:
        target = symbols.get(relationship["target"])
        target_text = describe_symbol(target) if target else relationship["target"]
    else:
        target_text = relationship["targetFallback"]
    return f"{source_text} --{relationship['kind']}--> {target_text}"


def remap_relationship(
    relationship: dict[str, str], identity_map: dict[str, str]
) -> dict[str, str]:
    remapped = dict(relationship)
    remapped["source"] = identity_map.get(remapped["source"], remapped["source"])
    if "target" in remapped:
        remapped["target"] = identity_map.get(remapped["target"], remapped["target"])
    return remapped


def compare_baseline(expected: dict[str, Any], actual: dict[str, Any]) -> bool:
    expected_symbols = {symbol["identity"]: symbol for symbol in expected["symbols"]}
    actual_symbols = {symbol["identity"]: symbol for symbol in actual["symbols"]}
    exact_identities = sorted(set(expected_symbols) & set(actual_symbols))
    identity_map = {identity: identity for identity in exact_identities}

    changed_symbols: list[str] = []
    for identity in exact_identities:
        if expected_symbols[identity] != actual_symbols[identity]:
            changed_symbols.append(
                f"{describe_symbol(actual_symbols[identity])} ({changed_fields(expected_symbols[identity], actual_symbols[identity])})"
            )

    expected_only = [
        expected_symbols[identity]
        for identity in sorted(set(expected_symbols) - set(actual_symbols))
    ]
    actual_only = [
        actual_symbols[identity]
        for identity in sorted(set(actual_symbols) - set(expected_symbols))
    ]
    expected_groups: dict[tuple[Any, ...], list[dict[str, Any]]] = defaultdict(list)
    actual_groups: dict[tuple[Any, ...], list[dict[str, Any]]] = defaultdict(list)
    for symbol in expected_only:
        expected_groups[
            (symbol["context"], symbol["kind"], tuple(symbol["path"]), symbol["role"])
        ].append(symbol)
    for symbol in actual_only:
        actual_groups[
            (symbol["context"], symbol["kind"], tuple(symbol["path"]), symbol["role"])
        ].append(symbol)

    removed_symbols: list[str] = []
    added_symbols: list[str] = []
    for group in sorted(set(expected_groups) | set(actual_groups)):
        expected_group = expected_groups.get(group, [])
        actual_group = actual_groups.get(group, [])
        if len(expected_group) == 1 and len(actual_group) == 1:
            old = expected_group[0]
            new = actual_group[0]
            identity_map[old["identity"]] = new["identity"]
            changed_symbols.append(
                f"{describe_symbol(old)} -> {describe_symbol(new)} ({changed_fields(old, new)})"
            )
        else:
            removed_symbols.extend(describe_symbol(symbol) for symbol in expected_group)
            added_symbols.extend(describe_symbol(symbol) for symbol in actual_group)

    expected_relationships = {
        relationship_sort_key(remap_relationship(relationship, identity_map)): remap_relationship(
            relationship, identity_map
        )
        for relationship in expected["relationships"]
    }
    actual_relationships = {
        relationship_sort_key(relationship): relationship
        for relationship in actual["relationships"]
    }
    relationship_symbols = dict(expected_symbols)
    relationship_symbols.update(actual_symbols)
    removed_relationships = [
        describe_relationship(expected_relationships[key], relationship_symbols)
        for key in sorted(set(expected_relationships) - set(actual_relationships))
    ]
    added_relationships = [
        describe_relationship(actual_relationships[key], relationship_symbols)
        for key in sorted(set(actual_relationships) - set(expected_relationships))
    ]

    if not (
        changed_symbols
        or removed_symbols
        or added_symbols
        or removed_relationships
        or added_relationships
    ):
        print(
            f"Public API baseline matches: {actual['symbolCount']} symbols, "
            f"{actual['relationshipCount']} relationships."
        )
        return True

    print(
        "ERROR: Public API baseline drift: "
        f"{len(added_symbols)} added, {len(removed_symbols)} removed, "
        f"{len(changed_symbols)} changed symbol(s); "
        f"{len(added_relationships)} added, {len(removed_relationships)} removed relationship(s).",
        file=sys.stderr,
    )
    emit_diagnostics("added symbol", sorted(added_symbols))
    emit_diagnostics("removed symbol", sorted(removed_symbols))
    emit_diagnostics("changed symbol", sorted(changed_symbols))
    emit_diagnostics("added relationship", sorted(added_relationships))
    emit_diagnostics("removed relationship", sorted(removed_relationships))
    return False


def atomically_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.chmod(temporary_path, 0o644)
        os.replace(temporary_path, path)
    except OSError as error:
        raise BaselineError(f"cannot atomically write baseline '{path}': {error}") from error
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Normalize and compare MarkdownKit public API symbol graph baselines."
    )
    parser.add_argument("--input-dir", required=True, type=Path)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--platform", required=True, choices=sorted(PLATFORM_CONFIGS))
    parser.add_argument("--module", default="MarkdownKit")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--record", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    actual = normalize_graphs(args.input_dir, args.module, args.platform)
    if args.record:
        atomically_write(args.baseline, canonical_json(actual))
        print(
            f"Recorded public API baseline: {args.baseline} "
            f"({actual['symbolCount']} symbols, {actual['relationshipCount']} relationships)."
        )
        return 0
    expected = validate_baseline(args.baseline, args.module, args.platform)
    return 0 if compare_baseline(expected, actual) else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except BaselineError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
