# MarkdownKit Benchmark Baseline

**Date**: 2026-02-27  
**Platform**: macOS · arm64 (Apple Silicon)  
**Harness**: `BenchmarkHarness` (warmup=3, iterations=20, `mach_absolute_time`)  
**Commit**: `123c77b+local`

## Phase 1: Parse

| Operation | Avg | P50 | P95 | Mem |
|-----------|-----|-----|-----|-----|
| parse(small) | 0.244ms | 0.238ms | 0.288ms | 16KB |
| parse(medium) | 1.61ms | 1.65ms | 1.75ms | 32KB |
| parse(large) | 13.17ms | 13.34ms | 13.61ms | 32KB |
| parse(code-heavy) | 0.266ms | 0.269ms | 0.293ms | ~0 |
| parse(table-heavy) | 13.24ms | 13.24ms | 13.53ms | 32KB |
| parse(math-heavy) | 0.565ms | 0.560ms | 0.590ms | 16KB |
| parse(details-heavy) | 2.19ms | 2.19ms | 2.27ms | 32KB |
| parse(diagram-heavy) | 0.308ms | 0.299ms | 0.352ms | 48KB |
| parse(tasklist-heavy) | 7.01ms | 6.96ms | 7.38ms | 32KB |

## Phase 2: Layout

| Operation | Avg | P50 | P95 | Mem |
|-----------|-----|-----|-----|-----|
| solve(small) | 0.786ms | 0.770ms | 0.928ms | 16KB |
| solve(medium) | 231.5ms | 231.0ms | 237.4ms | 144KB |
| solve(large) | 34.60ms | 34.30ms | 36.77ms | 32KB |
| solve(code-heavy) | 16.85ms | 16.77ms | 17.56ms | ~0 |
| solve(table-heavy) | 18.87ms | 18.88ms | 19.34ms | 16KB |
| solve(math-heavy) | 72.07ms | 71.24ms | 75.76ms | 688KB |
| solve(details-heavy) | 1.86ms | 1.82ms | 2.08ms | ~0 |
| solve(diagram-heavy) | 6.13ms | 6.08ms | 6.57ms | 144KB |
| solve(tasklist-heavy) | 7.38ms | 7.37ms | 7.59ms | 16KB |

## Cache Performance

| Operation | Avg | P50 | P95 | Mem |
|-----------|-----|-----|-----|-----|
| solve(cold)(medium) | 228.1ms | 228.1ms | 232.2ms | 144KB |
| solve(warm)(medium) | 0.006ms | 0.006ms | 0.007ms | ~0 |

### Cache Eviction Modes

| Operation | Avg | P50 | P95 | Mem |
|-----------|-----|-----|-----|-----|
| solve(cold-large)(medium) | 3450.7ms | 3446.8ms | 3480.8ms | 112KB |
| solve(warm-large)(medium) | 0.039ms | 0.037ms | 0.053ms | ~0 |
| solve(tiny-thrash)(medium) | 5446.6ms | 6913.0ms | 6961.3ms | 192KB |

### Cache Micro Operations

| Operation | Avg | P50 | P95 | Mem |
|-----------|-----|-----|-----|-----|
| getLayout(hit)(medium) | 0.004ms | 0.003ms | 0.012ms | ~0 |
| getLayout(miss)(medium) | 0.003ms | 0.002ms | 0.003ms | ~0 |
| setLayout()(medium) | 0.002ms | 0.002ms | 0.003ms | ~0 |
| clear()(medium) | 0.000ms | 0.000ms | 0.000ms | ~0 |

## Per-Node-Type Layout

| Node Type | Avg | P50 | P95 | Mem |
|-----------|-----|-----|-----|-----|
| headers | 1.58ms | 1.56ms | 1.79ms | 32KB |
| paragraphs | 2.90ms | 2.86ms | 3.21ms | 32KB |
| code-blocks | 17.09ms | 17.13ms | 17.63ms | 32KB |
| unordered-lists | 1.83ms | 1.80ms | 2.00ms | 16KB |
| ordered-lists | 1.80ms | 1.79ms | 1.95ms | ~0 |
| blockquotes | 1.84ms | 1.80ms | 1.97ms | ~0 |
| tables | 3.36ms | 3.35ms | 3.73ms | 16KB |
| thematic-breaks | 1.10ms | 1.08ms | 1.22ms | 16KB |
| details | 1.01ms | 1.00ms | 1.11ms | ~0 |
| diagrams | 3.91ms | 3.84ms | 4.65ms | 112KB |
| task-lists | 3.77ms | 3.73ms | 4.31ms | ~0 |
| math-blocks | 99.61ms | 99.71ms | 101.8ms | 224KB |

## Per-Syntax Tiered (simple / complex / extreme)

| Syntax | Simple | Complex | Extreme | Extreme Mem |
|--------|--------|---------|---------|-------------|
| header | 0.050ms | 0.552ms | 4.38ms | ~0 |
| paragraph | 0.045ms | 0.494ms | 7.49ms | ~0 |
| code-block | 0.732ms | 12.97ms | 248.1ms | 64KB |
| unordered-list | 0.146ms | 1.38ms | 8.56ms | 96KB |
| ordered-list | 0.150ms | 1.59ms | 8.58ms | 32KB |
| blockquote | 0.069ms | 0.499ms | 4.97ms | 16KB |
| table | 0.288ms | 2.04ms | 14.26ms | 32KB |
| thematic-break | 0.053ms | 0.484ms | 2.43ms | 16KB |
| inline-mix | 0.059ms | 0.506ms | 3.03ms | ~0 |
| task-list | 0.221ms | 2.05ms | 11.23ms | ~0 |
| details | 0.053ms | 0.772ms | 3.37ms | 16KB |
| diagram | 0.186ms | 3.79ms | 19.47ms | ~0 |
| math | 3.01ms | 67.97ms | 447.8ms | 112KB |

## Input Size Scaling

| Lines | Parse | Layout | Combined |
|-------|-------|--------|----------|
| 10 | 0.915ms | 1.39ms | ~2.3ms |
| 50 | 4.47ms | 5.35ms | ~9.8ms |
| 200 | 17.80ms | 20.47ms | ~38.3ms |
| 1000 | 87.92ms | 96.30ms | ~184.2ms |

Scaling characteristic: **O(n)** for both parse and layout.

## Width Scaling (medium fixture)

| Width | Avg | P95 |
|-------|-----|-----|
| 320px | 233.2ms | 236.1ms |
| 600px | 232.8ms | 236.3ms |
| 800px | 233.2ms | 237.0ms |
| 1024px | 228.2ms | 232.8ms |

Width impact remains low for this fixture.

## Plugin Composition (Parse Avg)

| Fixture | 0 plugins | 1 plugin | 2 plugins | 3 plugins |
|---------|-----------|----------|-----------|-----------|
| large | 6.88ms | 9.07ms | 10.08ms | 13.25ms |
| math-heavy | 0.268ms | 0.384ms | 0.418ms | 0.569ms |
| diagram-heavy | 0.165ms | 0.194ms | 0.218ms | 0.277ms |
| details-heavy | 0.825ms | 1.06ms | 1.15ms | 2.14ms |

## Concurrency

| Mode | Avg | Speedup |
|------|-----|---------|
| sequential-4x (medium) | 943.0ms | 1.0x |
| concurrent-4x (medium) | 237.5ms | 4.0x |
| sequential-8x (large) | 333.8ms | 1.0x |
| concurrent-8x (large) | 105.7ms | 3.2x |

## Notes

1. MathJax emitted repeated warnings for `\binom` in `math-heavy` (`Undefined control sequence`).  
2. Benchmark regression gating is enforced in `BenchmarkRegressionGuard` with:
   - `maxSlowdownFactor = 3.0`
   - `absoluteSlackMs = 5.0`
3. This baseline was produced from a local working tree (`+local`).

## Reproduction

```bash
swift test --filter "MarkdownKitBenchmarkTests/testBenchmarkFullReport"
swift test --filter "BenchmarkNodeTypeTests/testDeepBenchmarkFullReport"
swift test --filter "BenchmarkNodeTypeTests/testPerSyntaxTieredBenchmark"
swift test --filter "BenchmarkCacheTests"
```
