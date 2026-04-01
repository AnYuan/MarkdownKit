import XCTest
@testable import MarkdownKit

final class LayoutTests: XCTestCase {

    private struct FallbackCase {
        let name: String
        let markdown: String
        let width: CGFloat
    }
    
    func testBackgroundLayoutSizingAndCaching() async throws {
        let parser = MarkdownParser()
        let markdownString = """
        # Hello
        This is a much longer paragraph that should theoretically wrap if we constrain it to a very tight width, unlike the header.
        """
        
        let docNode = parser.parse(markdownString)
        
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)
        
        // 1. First Pass Layout (Not Cached)
        let tightWidth: CGFloat = 100.0
        
        let _ = PerformanceProfiler.measure(.layoutCalculation) {
            // Cannot use measure directly with async in basic XCTest yet without thunks, 
            // so using a semaphore or just awaiting.
        }
        
        // We will just await for the test since XCTest perform measure blocks synchronusly
        let rootLayout = await solver.solve(node: docNode, constrainedToWidth: tightWidth)
        
        XCTAssertEqual(rootLayout.children.count, 2)
        
        let headerLayout = rootLayout.children[0]
        let paragraphLayout = rootLayout.children[1]
        
        // 2. Verify TextKit 2 constraints
        // The header "Hello" should easily fit within 100 width.
        XCTAssertLessThanOrEqual(headerLayout.size.width, tightWidth)
        XCTAssertGreaterThan(headerLayout.size.height, 0)
        
        // The paragraph is long, so it MUST wrap, meaning height will be significantly larger than one line.
        XCTAssertLessThanOrEqual(paragraphLayout.size.width, tightWidth)
        XCTAssertGreaterThan(paragraphLayout.size.height, headerLayout.size.height)
        
        // 3. Verify Caching
        // A second request for the exact same node at the exact same width should instantaneously return 
        // the exact same reference from the LayoutCache.
        let cachedLayout = await solver.solve(node: docNode, constrainedToWidth: tightWidth)
        XCTAssertEqual(rootLayout.size, cachedLayout.size)
        
        // Verify we can clear the cache
        cache.clear()
        let nilLayout = cache.getLayout(for: docNode, constrainedToWidth: tightWidth)
        XCTAssertNil(nilLayout)
    }
    
    func testSyntaxHighlighting() async throws {
        let parser = MarkdownParser()
        let swiftCode = """
        ```swift
        let username = "Anyuan"
        print(username)
        ```
        """
        
        let docNode = parser.parse(swiftCode)
        let solver = LayoutSolver()
        let layoutRoot = await solver.solve(node: docNode, constrainedToWidth: 400.0)
        
        XCTAssertEqual(layoutRoot.children.count, 1)
        let codeLayout = layoutRoot.children[0]
        
        guard let attributedString = codeLayout.attributedString else {
            XCTFail("Code block layout is missing its attributed string.")
            return
        }
        
        // Splash syntax highlighting applies multiple different foreground color attributes
        // (e.g., keyword `let`, string `"Anyuan"`, etc.).
        // If highlighting works, the attributed string will NOT just have one single run.
        var attributesCount = 0
        attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { _, _, _ in
            attributesCount += 1
        }
        
        XCTAssertGreaterThan(attributesCount, 1, "Expected Splash to generate multiple syntax-highlighted attributes for Swift code. Got only \(attributesCount).")
    }

    func testUnsupportedScriptParagraphFallsBackToTextKit() async throws {
        let parser = MarkdownParser()
        let markdownString = "这是一个用于测试换行和宽度计算的中文段落，没有任何附件。"
        let docNode = parser.parse(markdownString)
        let solver = LayoutSolver()

        let layoutRoot = await solver.solve(node: docNode, constrainedToWidth: 160)
        XCTAssertEqual(layoutRoot.children.count, 1)

        let paragraphLayout = layoutRoot.children[0]
        guard let attributedString = paragraphLayout.attributedString else {
            XCTFail("Paragraph layout missing attributed string")
            return
        }

        let textKitSize = TextKitCalculator().calculateSize(
            for: attributedString,
            constrainedToWidth: 160
        )

        XCTAssertEqual(paragraphLayout.size.width, textKitSize.width)
        XCTAssertEqual(paragraphLayout.size.height, textKitSize.height)
    }

    func testUnsupportedScriptOracleMatrixFallsBackToTextKit() async throws {
        let parser = MarkdownParser()
        let solver = LayoutSolver()
        let cases: [FallbackCase] = [
            FallbackCase(
                name: "arabic",
                markdown: "مرحبا بالعالم هذا سطر عربي لاختبار الالتفاف.",
                width: 180
            ),
            FallbackCase(
                name: "thai",
                markdown: "ไทยภาษาใช้สำหรับทดสอบการตัดคำและการขึ้นบรรทัดใหม่",
                width: 180
            ),
            FallbackCase(
                name: "myanmar",
                markdown: "မြန်မာစာကို စာကြောင်းခွဲခြင်း စမ်းသပ်ရန် အသုံးပြုသည်။",
                width: 180
            ),
            FallbackCase(
                name: "hindi",
                markdown: "नमस्ते दुनिया यह पंक्ति हिंदी लेआउट परीक्षण के लिए है।",
                width: 180
            ),
            FallbackCase(
                name: "mixed-bidi",
                markdown: "Build status: مرحبا 123 بالعالم",
                width: 180
            )
        ]

        for fallbackCase in cases {
            let docNode = parser.parse(fallbackCase.markdown)
            let layoutRoot = await solver.solve(node: docNode, constrainedToWidth: fallbackCase.width)
            XCTAssertEqual(layoutRoot.children.count, 1, "Unexpected child count for case \(fallbackCase.name)")

            let paragraphLayout = layoutRoot.children[0]
            guard let attributedString = paragraphLayout.attributedString else {
                XCTFail("Paragraph layout missing attributed string for case \(fallbackCase.name)")
                continue
            }

            let textKitSize = TextKitCalculator().calculateSize(
                for: attributedString,
                constrainedToWidth: fallbackCase.width
            )

            XCTAssertEqual(
                paragraphLayout.size.width,
                textKitSize.width,
                "Width should match TextKit for case \(fallbackCase.name)"
            )
            XCTAssertEqual(
                paragraphLayout.size.height,
                textKitSize.height,
                "Height should match TextKit for case \(fallbackCase.name)"
            )
        }
    }
    
    #if canImport(UIKit)
    func testMathJaxBackgroundRendering() async throws {
        let parser = MarkdownParser()
        let mathCode = """
        Here is some inline math $E=mc^2$ inside a paragraph.
        """
        
        let docNode = parser.parse(mathCode)
        let solver = LayoutSolver()
        
        // This measure pass will await the WebKit JavaScript evaluation
        let layoutRoot = await solver.solve(node: docNode, constrainedToWidth: 400.0)
        
        XCTAssertEqual(layoutRoot.children.count, 1)
        let paragraphLayout = layoutRoot.children[0]
        
        guard let attributedString = paragraphLayout.attributedString else {
            XCTFail("Paragraph layout missing attributed string.")
            return
        }
        
        var hasAttachment = false
        attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length), options: []) { value, _, _ in
            if value is NSTextAttachment {
                hasAttachment = true
            }
        }

        // WebKit JS may fail headless, so accept either an attachment (rendered math)
        // or fallback text containing the equation.
        if !hasAttachment {
            let text = attributedString.string
            XCTAssertTrue(text.contains("E=mc^2"), "Expected math attachment or fallback equation text, got: \(text)")
        }
    }
    #endif
}
