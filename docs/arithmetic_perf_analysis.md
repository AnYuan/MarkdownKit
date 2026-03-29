## Arithmetic Engine Perf Analysis

**Before (TextKit):**
solve(paragraphs) | Avg 3.92ms | P50 3.89ms | P95 4.31ms

**After (Arithmetic Engine PoC):**
solve(paragraphs) | Avg 3.91ms | P50 3.94ms | P95 4.24ms

**Conclusion:**
There is no significant performance difference in this initial PoC phase. This is largely because the `ArithmeticTextCalculator.prepare` function is currently still creating lots of short-lived Swift String instances and doing a character-by-character scan before querying `CTFontGetAdvancesForGlyphs`.

Even though we successfully bypassed TextKit's lock and large `NSTextStorage` instantiation costs, the overhead of looping over Swift Strings in the current naive tokenizer limits the theoretical gains for standard paragraphs. 

To truly out-scale TextKit in the future, the tokenizer needs to be rewritten using a highly optimized, allocation-free low-level character buffer (e.g. `utf16` direct pointers) instead of creating `String(char)`. However, the mathematical SoA (Structure of Arrays) architectural foundation is now completely implemented and correctly routes pure text away from TextKit, setting the stage for future micro-optimizations!