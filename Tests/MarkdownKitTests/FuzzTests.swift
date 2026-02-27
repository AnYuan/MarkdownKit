import XCTest
@testable import MarkdownKit

final class FuzzTests: XCTestCase {
    
    // A deterministic seed-based PRNG to ensure random fuzzing is reproducible if it fails.
    struct LCG {
        var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            state = 6364136223846793005 &* state &+ 1442695040888963407
            return state
        }
        mutating func next(upperBound: Int) -> Int {
            return Int(next() % UInt64(upperBound))
        }
    }
    
    let hostileTokens = [
        "> ", ">>>>> ", "- ", "1. ", "    ", "\t", "```swift\n", "```\n",
        "# ", "###### ", "![alt](url)", "[link](url)", " * ", " _ ", " ** ",
        " ~~ ", " $$ ", " $ ", "<details><summary>", "</summary>", "</details>",
        "| a | b |\n|---|---|", "\n\n", " \n", "\u{0000}", "\u{0003}", "\r\n",
        " javascript:alert(1) ", "<script>alert(1)</script>", "![a](javascript:alert)",
        "\\", "\\\\", "[", "]", "(", ")", "<", ">", "&", "*"
    ]
    
    func testFuzzParserWithRandomPermutations() {
        let parser = MarkdownParser()
        let iterations = 1000  // Generate 1000 completely random chaotic topologies
        let maxTokensPerPayload = 200
        
        var rng = LCG(seed: 42) // Fixed seed so failures are perfectly reproducible
        
        for iteration in 0..<iterations {
            var payload = ""
            let numTokens = rng.next(upperBound: maxTokensPerPayload) + 10
            
            for _ in 0..<numTokens {
                let tokenIndex = rng.next(upperBound: hostileTokens.count)
                payload += hostileTokens[tokenIndex]
            }
            
            // The assertion here is simply that `parse` DOES NOT CRASH.
            // Under no circumstances should garbage input cause a fatalError or deep recursion crash.
            let doc = parser.parse(payload)
            XCTAssertNotNil(doc, "Iteration \(iteration) produced a nil document instead of successfully parsing garbage data.")
        }
    }
}
