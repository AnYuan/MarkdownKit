#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || {
    printf 'FAIL: could not resolve the script directory.\n' >&2
    exit 1
}
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd) || {
    printf 'FAIL: could not resolve the repository root.\n' >&2
    exit 1
}
cd "$REPO_ROOT" || {
    printf 'FAIL: could not enter repository root: %s\n' "$REPO_ROOT" >&2
    exit 1
}

failures=0

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

parse_knowledge_count() {
    awk '
        {
            remainder = $0
            while (match(remainder, /\*\*[^*]*\*\* discoverable tests/)) {
                field = substr(remainder, RSTART, RLENGTH)
                value = field
                sub(/^\*\*/, "", value)
                sub(/\*\* discoverable tests$/, "", value)
                count++
                last_value = value
                remainder = substr(remainder, RSTART + RLENGTH)
            }
        }
        END {
            if (count != 1) {
                printf "expected exactly one **N** discoverable tests field, found %d\n", count > "/dev/stderr"
                exit 1
            }
            if (last_value !~ /^[0-9]+$/) {
                printf "discoverable test count is not numeric: %s\n", last_value > "/dev/stderr"
                exit 1
            }
            print last_value
        }
    ' "$1"
}

parse_coverage_count() {
    awk '
        /^[[:space:]]*\|/ && index($0, "swift test list") {
            row_count++
            cell_count = split($0, cells, "|")
            command_cells = 0
            row_value = ""

            for (i = 1; i <= cell_count; i++) {
                if (cells[i] ~ /swift test list/) {
                    command_cells++
                    if (i < cell_count) {
                        row_value = cells[i + 1]
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", row_value)
                    }
                }
            }

            if (command_cells != 1) {
                malformed = 1
            }
            last_value = row_value
        }
        END {
            if (row_count != 1) {
                printf "expected exactly one table row containing swift test list, found %d\n", row_count > "/dev/stderr"
                exit 1
            }
            if (malformed || last_value !~ /^[0-9]+$/) {
                printf "swift test list table count is not numeric: %s\n", last_value > "/dev/stderr"
                exit 1
            }
            print last_value
        }
    ' "$1"
}

test_output=""
test_status=0
if test_output=$(swift test list); then
    pass '`swift test list` completed successfully'
else
    test_status=$?
    fail "\`swift test list\` exited with status $test_status"
fi

if [ -z "$test_output" ]; then
    fail '`swift test list` produced empty output'
fi

invalid_lines=$(printf '%s\n' "$test_output" | awk '
    length($0) > 0 && $0 !~ /^MarkdownKitTests\.[[:alpha:]_][[:alnum:]_]*\/[[:alpha:]_][[:alnum:]_]*$/ {
        print
    }
')
if [ -n "$invalid_lines" ]; then
    fail '`swift test list` produced non-empty lines outside MarkdownKitTests.Class/testMethod'
    printf '%s\n' "$invalid_lines" | sed 's/^/  /' >&2
else
    pass '`swift test list` output uses MarkdownKitTests.Class/testMethod exclusively'
fi

actual_count=$(printf '%s\n' "$test_output" | awk '
    /^MarkdownKitTests\.[[:alpha:]_][[:alnum:]_]*\/[[:alpha:]_][[:alnum:]_]*$/ {
        count++
    }
    END {
        print count + 0
    }
')
if [ "$actual_count" -gt 0 ] 2>/dev/null; then
    pass "discovered a nonzero actual test count ($actual_count)"
else
    fail "actual discoverable test count is not positive ($actual_count)"
fi

KNOWLEDGE_FILE="docs/CodebaseKnowledge.md"
if [ ! -f "$KNOWLEDGE_FILE" ]; then
    fail "missing $KNOWLEDGE_FILE"
else
    knowledge_count=""
    if knowledge_count=$(parse_knowledge_count "$KNOWLEDGE_FILE"); then
        if [ "$knowledge_count" = "$actual_count" ]; then
            pass "$KNOWLEDGE_FILE matches the actual count ($actual_count)"
        else
            fail "$KNOWLEDGE_FILE documents $knowledge_count tests; actual count is $actual_count"
        fi
    else
        fail "$KNOWLEDGE_FILE has an invalid discoverable test count field"
    fi
fi

COVERAGE_FILE="docs/TestCoverage.md"
if [ ! -f "$COVERAGE_FILE" ]; then
    fail "missing $COVERAGE_FILE"
else
    coverage_count=""
    if coverage_count=$(parse_coverage_count "$COVERAGE_FILE"); then
        if [ "$coverage_count" = "$actual_count" ]; then
            pass "$COVERAGE_FILE matches the actual count ($actual_count)"
        else
            fail "$COVERAGE_FILE documents $coverage_count tests; actual count is $actual_count"
        fi
    else
        fail "$COVERAGE_FILE has an invalid swift test list table row"
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    fail 'python3 is required for the benchmark documentation check'
else
    benchmark_output=""
    if benchmark_output=$(python3 scripts/render_benchmark_baseline.py --check 2>&1); then
        pass 'benchmark baseline documentation matches its JSON source'
        if [ -n "$benchmark_output" ]; then
            printf '%s\n' "$benchmark_output"
        fi
    else
        benchmark_status=$?
        fail "benchmark baseline documentation check exited with status $benchmark_status"
        if [ -n "$benchmark_output" ]; then
            printf '%s\n' "$benchmark_output" >&2
        fi
    fi
fi

if [ "$failures" -eq 0 ]; then
    printf 'PASS: documentation freshness gate passed (%s discoverable tests).\n' "$actual_count"
    exit 0
fi

printf 'FAIL: documentation freshness gate found %s failure(s).\n' "$failures" >&2
exit 1
