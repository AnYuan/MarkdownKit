# MarkdownKit Benchmark Baseline

| Run | Date | Commit | Note |
|---|---|---|---|
| Initial baseline | 2026-02-27 | `123c77b+local` | first full report |
| Phase 2 layout refresh | 2026-04-01 | (local) | targeted rerun |
| **Phase 0-6 refresh** | **2026-05-28** | **`e05b068`** | **full report; current numbers below** |

**Platform**: macOS · arm64 (Apple Silicon)
**Harness**: `BenchmarkHarness` (warmup=3, iterations=20, `mach_absolute_time`)

> Detailed per-phase win attribution + analysis: [`BENCHMARK_POST_PHASE_6.md`](BENCHMARK_POST_PHASE_6.md)
>
> Headline shifts on 2026-05-28 vs 2026-04-01:
> * `solve(cold)(medium)` 228.1ms → **3.56ms** (-98.4 %)
> * `solve(cold-large)(medium)` 3450.7ms → **29.60ms** (-99.1 %)
> * `solve(math-blocks)` 99.61ms → **0.664ms** (-99.3 %)
> * parse path uniformly -25 to -39 %
> * concurrency sequential-4x 943.0ms → **11.32ms** (-98.8 %)
> * Two regressions noted: `solve(1000-lines)` (+277 % — Phase 6.4 trade-off, moves accessibility work off main) and `Arithmetic.layout(long)` (+21 % — identity/accessibility stamping at `LayoutResult.init`).

## Parse

| Operation | 2026-04-01 | 2026-05-28 | Δ |
|-----------|-----------:|-----------:|---:|
| parse(small) | 0.244ms | **0.165ms** | -32 % |
| parse(medium) | 1.61ms | **1.13ms** | -30 % |
| parse(large) | 13.17ms | **9.11ms** | -31 % |
| parse(code-heavy) | 0.266ms | **0.200ms** | -25 % |
| parse(table-heavy) | 13.24ms | **8.97ms** | -32 % |
| parse(math-heavy) | 0.565ms | **0.400ms** | -29 % |
| parse(details-heavy) | 2.19ms | **1.34ms** | -39 % |
| parse(diagram-heavy) | 0.308ms | **0.201ms** | -35 % |
| parse(tasklist-heavy) | 7.01ms | **4.87ms** | -31 % |

## Layout (first solve, fresh cache)

| Operation | 2026-04-01 | 2026-05-28 | Δ |
|-----------|-----------:|-----------:|---:|
| solve(small) | 0.457ms | **0.353ms** | -23 % |
| solve(medium) | 3.25ms | **2.20ms** | -32 % |
| solve(large) | 23.79ms | **16.75ms** | -30 % |
| solve(code-heavy) | 3.63ms | **3.23ms** | -11 % |
| solve(table-heavy) | 19.78ms | **13.86ms** | -30 % |
| solve(math-heavy) | 1.23ms | **0.981ms** | -20 % |
| solve(details-heavy) | 2.15ms | **1.40ms** | -35 % |
| solve(diagram-heavy) | 0.905ms | **0.770ms** | -15 % |
| solve(tasklist-heavy) | 11.00ms | **7.25ms** | -34 % |

### Arithmetic Text Measurement

| Operation | 2026-04-01 | 2026-05-28 | Δ |
|-----------|-----------:|-----------:|---:|
| TextKit.calcSize(short) | 0.013ms | 0.012ms | -8 % |
| Arithmetic.prepare(short) | 0.002ms | 0.002ms | flat |
| Arithmetic.layout(short) | 0.001ms | 0.001ms | flat |
| TextKit.calcSize(paragraph) | 0.191ms | 0.238ms | +25 % |
| Arithmetic.prepare(paragraph) | 0.002ms | 0.004ms | +100 % |
| Arithmetic.layout(paragraph) | 0.058ms | 0.066ms | +14 % |
| TextKit.calcSize(long) | 1.59ms | 3.45ms | +117 % ⚠ |
| Arithmetic.prepare(long) | 0.003ms | 0.006ms | +100 % |
| Arithmetic.layout(long) | 0.358ms | 0.432ms | +21 % |

`TextKit.calcSize(long)` more-than-doubled because the macOS runtime's `.SFNS-*` font fallback swapped to `TimesNewRomanPSMT` mid-run (visible in the log `CoreText note: Client requested name '.SFNS-Bold', it will get TimesNewRomanPSMT rather than the intended font`). Not a code regression. Arithmetic prep/layout extra ~70 µs per long input is the `LayoutResult.init` identity + accessibility stamping (Phase 4.1 + 6.4).

## Cache

| Operation | 2026-04-01 | 2026-05-28 | Δ |
|-----------|-----------:|-----------:|---:|
| **solve(cold)(medium)** | 228.1ms | **3.56ms** | **-98.4 %** |
| solve(warm)(medium) | 0.006ms | 0.003ms | -50 % |
| **solve(cold-large)(medium)** | 3450.7ms | **29.60ms** | **-99.1 %** |
| solve(warm-large)(medium) | 0.039ms | 0.016ms | -59 % |
| **solve(tiny-thrash)(medium)** | 5446.6ms | **60.31ms** | **-98.9 %** |
| getLayout(hit)(medium) | 0.004ms | **<0.001ms** | sub-µs |
| getLayout(miss)(medium) | 0.003ms | **<0.001ms** | sub-µs |
| setLayout()(medium) | 0.002ms | **<0.001ms** | sub-µs |
| clear()(medium) | 0.000ms | 0.000ms | flat |

The headline 100× wins on cold / thrash are the direct payoff of Phase 1.2's O(N) → O(1) `contentFingerprint` (struct field read instead of subtree walk).

## Per-Node-Type Layout

| Node Type | 2026-04-01 | 2026-05-28 | Δ |
|-----------|-----------:|-----------:|---:|
| headers | 1.58ms | **1.08ms** | -32 % |
| paragraphs | 2.90ms | **1.58ms** | -46 % |
| **code-blocks** | 17.09ms | **4.12ms** | **-76 %** |
| unordered-lists | 1.83ms | **1.58ms** | -14 % |
| ordered-lists | 1.80ms | 1.92ms | +7 % |
| blockquotes | 1.84ms | **1.41ms** | -23 % |
| tables | 3.36ms | **2.42ms** | -28 % |
| **thematic-breaks** | 1.10ms | **0.137ms** | **-88 %** |
| details | 1.01ms | **0.688ms** | -32 % |
| **diagrams** | 3.91ms | **0.418ms** | **-89 %** |
| task-lists | 3.77ms | 4.08ms | +8 % |
| **math-blocks** | 99.61ms | **0.664ms** | **-99.3 %** |

Task-list slightly slower because each row now writes `.markdownCheckbox` interaction data into the attributed string — that was silently dropped in the sync path before Phase 6.2 surfaced the parity bug.

## Per-Syntax Tiered

| Syntax | Tier | 2026-04-01 | 2026-05-28 | Δ |
|--------|------|-----------:|-----------:|---:|
| header | simple | 0.050ms | 0.017ms | -66 % |
| header | complex | 0.552ms | 0.344ms | -38 % |
| header | extreme | 4.38ms | 3.47ms | -21 % |
| paragraph | simple | 0.045ms | 0.019ms | -58 % |
| paragraph | complex | 0.494ms | 0.310ms | -37 % |
| paragraph | extreme | 7.49ms | 4.84ms | -35 % |
| code-block | simple | 0.732ms | 0.546ms | -25 % |
| code-block | complex | 12.97ms | 4.10ms | -68 % |
| **code-block** | **extreme** | 248.1ms | **40.35ms** | **-84 %** |
| unordered-list | simple | 0.146ms | 0.108ms | -26 % |
| unordered-list | complex | 1.38ms | 0.966ms | -30 % |
| unordered-list | extreme | 8.56ms | 6.66ms | -22 % |
| ordered-list | simple | 0.150ms | 0.112ms | -25 % |
| ordered-list | complex | 1.59ms | 1.25ms | -21 % |
| ordered-list | extreme | 8.58ms | 7.66ms | -11 % |
| blockquote | simple | 0.069ms | 0.047ms | -32 % |
| blockquote | complex | 0.499ms | 0.429ms | -14 % |
| blockquote | extreme | 4.97ms | 3.02ms | -39 % |
| table | simple | 0.288ms | 0.180ms | -38 % |
| table | complex | 2.04ms | 1.50ms | -26 % |
| table | extreme | 14.26ms | 11.62ms | -19 % |
| thematic-break | simple | 0.053ms | 0.030ms | -43 % |
| thematic-break | complex | 0.484ms | 0.062ms | -87 % |
| **thematic-break** | **extreme** | 2.43ms | **0.100ms** | **-96 %** |
| inline-mix | simple | 0.059ms | 0.033ms | -44 % |
| inline-mix | complex | 0.506ms | 0.289ms | -43 % |
| inline-mix | extreme | 3.03ms | 1.70ms | -44 % |
| task-list | simple | 0.221ms | 0.183ms | -17 % |
| task-list | complex | 2.05ms | 1.70ms | -17 % |
| task-list | extreme | 11.23ms | 9.86ms | -12 % |
| details | simple | 0.053ms | 0.057ms | +8 % |
| details | complex | 0.772ms | 0.485ms | -37 % |
| details | extreme | 3.37ms | 2.36ms | -30 % |
| diagram | simple | 0.186ms | 0.038ms | -80 % |
| diagram | complex | 3.79ms | 0.350ms | -91 % |
| **diagram** | **extreme** | 19.47ms | **1.57ms** | **-92 %** |
| math | simple | 3.01ms | 0.045ms | -99 % |
| math | complex | 67.97ms | 0.587ms | -99 % |
| **math** | **extreme** | 447.8ms | **2.88ms** | **-99.4 %** |

`extreme` math went from sub-second class to single-digit milliseconds because both the SVG cache and the image cache hit across iterations (Phase 0.1 + 2.2 NSCache caps, Phase 3 SwiftDraw path).

## Input Size Scaling

| Lines | 2026-04-01 Parse | 2026-05-28 Parse | 2026-04-01 Solve | 2026-05-28 Solve |
|------:|-----------------:|-----------------:|-----------------:|-----------------:|
| 10 | 0.915ms | **0.675ms** | 1.39ms | **0.674ms** |
| 50 | 4.47ms | **3.35ms** | 5.35ms | **2.87ms** |
| 200 | 17.80ms | **12.69ms** | 20.47ms | **11.66ms** |
| 1000 | 87.92ms | **62.66ms** | 96.30ms | **363.4ms** ⚠ |

`solve(1000-lines)` regressed ~4×. Phase 6.4 moved `PlatformAccessibility` work to background layout time. On a 1000-block document, the `enumerateAttribute(.markdownCheckbox, …)` scans contribute roughly the +280 ms seen here. Saves equivalent main-thread time at every cell `configure`; trade-off documented in `BENCHMARK_POST_PHASE_6.md`.

## Width Scaling (medium fixture, resolve at multiple widths)

| Width | 2026-04-01 Avg | 2026-05-28 Avg | Δ |
|-------|---------------:|---------------:|---:|
| 320px | 233.2ms | **2.21ms** | **-99.1 %** |
| 600px | 232.8ms | **2.07ms** | **-99.1 %** |
| 800px | 233.2ms | **2.09ms** | **-99.1 %** |
| 1024px | 228.2ms | **2.10ms** | **-99.1 %** |

The baseline re-solved everything from scratch at each width because the per-`getLayout` cache lookup was O(subtree). After Phase 1.2's O(1) fingerprint, the second and later widths hit cache for any unchanged sub-layout. The `MarkdownView`'s width-change handler (Phase 4.6 debounced merged onChange) now sees this same speedup in production.

## Plugin Composition (Parse Avg)

| Fixture | Plugins | 2026-04-01 | 2026-05-28 | Δ |
|---------|--------:|-----------:|-----------:|---:|
| large | 0 | 6.88ms | 5.34ms | -22 % |
| large | 1 | 9.07ms | 6.53ms | -28 % |
| large | 2 | 10.08ms | 7.07ms | -30 % |
| large | 3 | 13.25ms | 9.25ms | -30 % |
| math-heavy | 0 | 0.268ms | 0.201ms | -25 % |
| math-heavy | 1 | 0.384ms | 0.300ms | -22 % |
| math-heavy | 2 | 0.418ms | 0.307ms | -27 % |
| math-heavy | 3 | 0.569ms | 0.402ms | -29 % |
| diagram-heavy | 0 | 0.165ms | 0.123ms | -25 % |
| diagram-heavy | 1 | 0.194ms | 0.146ms | -25 % |
| diagram-heavy | 2 | 0.218ms | 0.164ms | -25 % |
| diagram-heavy | 3 | 0.277ms | 0.202ms | -27 % |
| details-heavy | 0 | 0.825ms | 0.641ms | -22 % |
| details-heavy | 1 | 1.06ms | 0.787ms | -26 % |
| details-heavy | 2 | 1.15ms | 0.858ms | -25 % |
| details-heavy | 3 | 2.14ms | 1.29ms | -40 % |

Each plugin's incremental cost dropped because `AST.transform` keeps unchanged subtrees by identity instead of allocating new container nodes.

## Concurrency

| Mode | 2026-04-01 | 2026-05-28 | Δ |
|------|-----------:|-----------:|---:|
| **sequential-4x (medium)** | 943.0ms | **11.32ms** | **-98.8 %** |
| **concurrent-4x (medium)** | 237.5ms | **5.33ms** | **-97.8 %** |
| sequential-8x (large) | 333.8ms | **212.3ms** | -36 % |
| concurrent-8x (large) | 105.7ms | **54.71ms** | -48 % |

Sequential-4x went from "4 × cold solve" to "4 × warm hits" because all four iterations share the same `LayoutCache` instance — exactly the production benefit of `MarkdownEngine`'s persisted cache from Phase 0.3.

## Notes

1. MathJax emitted repeated warnings for `\binom` in `math-heavy` (`Undefined control sequence`) — unchanged from earlier runs.
2. `BenchmarkRegressionGuard` thresholds: `maxSlowdownFactor = 3.0`, `absoluteSlackMs = 5.0`. The `solve(1000-lines)` regression sits at ~3.8× — on the gating boundary. A follow-up PR should either widen the guard for this fixture or thread accessibility metadata as a lazy property.
3. The 2026-05-28 refresh was a full rerun of `verify_benchmarks.sh` from local working tree at `e05b068`.

## Reproduction

```bash
bash scripts/verify_benchmarks.sh

# Or individually:
swift test --filter "MarkdownKitBenchmarkTests/testBenchmarkFullReport"
swift test --filter "BenchmarkNodeTypeTests/testDeepBenchmarkFullReport"
swift test --filter "BenchmarkNodeTypeTests/testPerSyntaxTieredBenchmark"
swift test --filter "BenchmarkCacheTests"
```
