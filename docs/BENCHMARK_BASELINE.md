# MarkdownKit Benchmark Baseline

> **Generated file — do not hand-edit.** Produced by `scripts/render_benchmark_baseline.py` from [`Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json`](../Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json), the single machine-readable source of truth consumed by both this document and `BenchmarkRegressionGuard` in the Swift test target. Edit the JSON and rerun `python3 scripts/render_benchmark_baseline.py` to refresh this file.

**Version**: `2026-07-20@ad80fcc` · **Recorded**: 2026-07-20 · **Commit**: `ad80fcc`

**Platform**: macOS 26.5.2 · arm64 (Apple M5 Max)
**Harness**: `BenchmarkHarness` (warmup=3, iterations=20, clock=`mach_absolute_time`)
**Recording**: 5 independent, isolated Release process runs per canonical workload; `averageMilliseconds` is the median of per-process averages across those 5 runs.

## Regression Policy

`BenchmarkRegressionGuard` fails a benchmark when its measured average exceeds:

```
budget = max(baseline * maxSlowdownFactor, baseline + absoluteSlackMilliseconds)
```

* `maxSlowdownFactor` = 2
* `absoluteSlackMilliseconds` = 2
* A measurement's `enforceAverageBudget` may be `false` (omitted means `true`) to exempt it from this absolute budget when a relational contract is the more meaningful guard for that workload; see the `Average Guard` column below.

> The 2x + 2ms envelope is a conservative global fallback. Recorded averages remain specific to the platform above and are not normalized across hardware; p95, max, and whole-process RSS remain informational.

> Detailed per-phase win attribution + historical analysis (archival, not authoritative): [`BENCHMARK_POST_PHASE_6.md`](BENCHMARK_POST_PHASE_6.md)

## Parse (`core.parse`)

| Key | Average | Average Guard |
|---|---:|---|
| `parse(code-heavy)` | 0.1ms | budget-enforced |
| `parse(details-heavy)` | 0.739ms | budget-enforced |
| `parse(diagram-heavy)` | 0.105ms | budget-enforced |
| `parse(large)` | 4.7ms | budget-enforced |
| `parse(math-heavy)` | 0.216ms | budget-enforced |
| `parse(medium)` | 0.602ms | budget-enforced |
| `parse(small)` | 0.09ms | budget-enforced |
| `parse(table-heavy)` | 4.24ms | budget-enforced |
| `parse(tasklist-heavy)` | 2.43ms | budget-enforced |

## Layout (`core.layout`)

| Key | Average | Average Guard |
|---|---:|---|
| `solve(code-heavy)` | 2.67ms | budget-enforced |
| `solve(details-heavy)` | 1.24ms | budget-enforced |
| `solve(diagram-heavy)` | 0.75ms | budget-enforced |
| `solve(large)` | 11.03ms | budget-enforced |
| `solve(math-heavy)` | 0.917ms | budget-enforced |
| `solve(medium)` | 1.82ms | budget-enforced |
| `solve(small)` | 0.277ms | budget-enforced |
| `solve(table-heavy)` | 13.6ms | budget-enforced |
| `solve(tasklist-heavy)` | 6.84ms | budget-enforced |

## Cache (`core.cache`)

| Key | Average | Average Guard |
|---|---:|---|
| `solve(cold)(medium)` | 1.71ms | budget-enforced |
| `solve(warm)(medium)` | 0.001ms | relational-only (`assertWarmCacheImproves`: warm < cold) |

## Concurrency (`deep.concurrency`)

| Key | Average | Average Guard |
|---|---:|---|
| `concurrent-4x(medium)` | 4.68ms | budget-enforced |
| `concurrent-8x(large)` | 47.92ms | budget-enforced |
| `sequential-4x(medium)` | 8.04ms | budget-enforced |
| `sequential-8x(large)` | 102.9ms | budget-enforced |

## Coordinator Streaming (`coordinator.streaming`)

| Key | Average | Average Guard |
|---|---:|---|
| `latest-settled(large-3-updates)` | 28.82ms | budget-enforced |

## Canonical Benchmark Gate

> The baseline above was recorded from isolated Release-process executions (see **Recording** above); it is the authoritative current guard.

```bash
bash scripts/verify_benchmarks.sh
```
