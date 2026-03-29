## Arithmetic Engine Perf Analysis

**Before (TextKit):**
solve(paragraphs) | Avg 3.92ms | P50 3.89ms | P95 4.31ms

**After (Arithmetic Engine PoC - Naive String allocs):**
solve(paragraphs) | Avg 3.91ms | P50 3.94ms | P95 4.24ms

**After (Allocation-Free UTF-16 Scanner):**
solve(paragraphs) | Avg 3.19ms | P50 3.17ms | P95 3.44ms

**Conclusion:**
By rewriting the segment preparation logic to use a pure, allocation-free UTF-16 buffer scan (`[UniChar]`) and passing pointers directly to `CTFontGetGlyphsForCharacters`, we've bypassed the heavy toll of Swift's `String` allocation and substring operations.

This yielded a **~18.6% performance improvement** (3.92ms -> 3.19ms) in overall layout throughput for paragraph nodes compared to the baseline `TextKitCalculator`, while completely eliminating the `os_unfair_lock` bottleneck! 

We now have an extremely fast, lock-free, concurrent SoA arithmetic layout engine for pure text, heavily inspired by the architecture of `@chenglou/pretext`.