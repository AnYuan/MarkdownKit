# MarkdownKit Benchmark Baseline

> **Generated file — do not hand-edit.** Produced by `scripts/render_benchmark_baseline.py` from [`Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json`](../Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json), the single machine-readable source of truth consumed by both this document and `BenchmarkRegressionGuard` in the Swift test target. Edit the JSON and rerun `python3 scripts/render_benchmark_baseline.py` to refresh this file.

**Version**: `2026-05-28@e05b068` · **Recorded**: 2026-05-28 · **Commit**: `e05b068`

**Platform**: macOS · arm64 (Apple Silicon)
**Harness**: `BenchmarkHarness` (warmup=3, iterations=20, clock=`mach_absolute_time`)

## Regression Policy

`BenchmarkRegressionGuard` fails a benchmark when its measured average exceeds:

```
budget = max(baseline * maxSlowdownFactor, baseline + absoluteSlackMilliseconds)
```

* `maxSlowdownFactor` = 3
* `absoluteSlackMilliseconds` = 5

> Detailed per-phase win attribution + historical analysis (archival, not authoritative): [`BENCHMARK_POST_PHASE_6.md`](BENCHMARK_POST_PHASE_6.md)

## Parse (`core.parse`)

| Key | Average |
|---|---:|
| `parse(code-heavy)` | 0.2ms |
| `parse(details-heavy)` | 1.34ms |
| `parse(diagram-heavy)` | 0.201ms |
| `parse(large)` | 9.11ms |
| `parse(math-heavy)` | 0.4ms |
| `parse(medium)` | 1.13ms |
| `parse(small)` | 0.165ms |
| `parse(table-heavy)` | 8.97ms |
| `parse(tasklist-heavy)` | 4.87ms |

## Layout (`core.layout`)

| Key | Average |
|---|---:|
| `solve(code-heavy)` | 3.23ms |
| `solve(details-heavy)` | 1.4ms |
| `solve(diagram-heavy)` | 0.77ms |
| `solve(large)` | 16.75ms |
| `solve(math-heavy)` | 0.981ms |
| `solve(medium)` | 2.2ms |
| `solve(small)` | 0.353ms |
| `solve(table-heavy)` | 13.86ms |
| `solve(tasklist-heavy)` | 7.25ms |

## Cache (`core.cache`)

| Key | Average |
|---|---:|
| `solve(cold)(medium)` | 3.56ms |
| `solve(warm)(medium)` | 0.003ms |

## Concurrency (`deep.concurrency`)

| Key | Average |
|---|---:|
| `concurrent-4x(medium)` | 5.33ms |
| `concurrent-8x(large)` | 54.71ms |
| `sequential-4x(medium)` | 11.32ms |
| `sequential-8x(large)` | 212.3ms |

## Reproduction

```bash
bash scripts/verify_benchmarks.sh

# Or individually:
swift test --filter "MarkdownKitBenchmarkTests/testBenchmarkFullReport"
swift test --filter "BenchmarkNodeTypeTests/testDeepBenchmarkFullReport"
swift test --filter "BenchmarkNodeTypeTests/testPerSyntaxTieredBenchmark"
swift test --filter "BenchmarkCacheTests"
```
