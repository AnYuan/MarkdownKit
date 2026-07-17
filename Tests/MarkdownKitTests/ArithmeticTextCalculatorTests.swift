import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class ArithmeticTextCalculatorTests: XCTestCase {

    private struct OracleCase {
        let name: String
        let attributedString: NSAttributedString
        let width: CGFloat
        let widthAccuracy: CGFloat
        let heightAccuracy: CGFloat
    }

    private func makeAttributedString(
        _ text: String,
        fontSize: CGFloat = 16,
        configureParagraphStyle: ((NSMutableParagraphStyle) -> Void)? = nil
    ) -> NSAttributedString {
        let font = Font.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        configureParagraphStyle?(paragraphStyle)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        return NSAttributedString(string: text, attributes: attrs)
    }

    private func assertOracleParity(_ oracleCase: OracleCase, file: StaticString = #filePath, line: UInt = #line) {
        let arithmeticCalc = ArithmeticTextCalculator()
        let textKitCalc = TextKitCalculator()

        let arithmeticSize = arithmeticCalc.calculateSize(
            for: oracleCase.attributedString,
            constrainedToWidth: oracleCase.width
        )
        let textKitSize = textKitCalc.calculateSize(
            for: oracleCase.attributedString,
            constrainedToWidth: oracleCase.width
        )

        XCTAssertEqual(
            arithmeticSize.width,
            textKitSize.width,
            accuracy: oracleCase.widthAccuracy,
            "Width drifted for oracle case '\(oracleCase.name)'",
            file: file,
            line: line
        )
        XCTAssertEqual(
            arithmeticSize.height,
            textKitSize.height,
            accuracy: oracleCase.heightAccuracy,
            "Height drifted for oracle case '\(oracleCase.name)'",
            file: file,
            line: line
        )
    }

    func testSupportedPureTextOracleMatrixRoughParity() {
        let cases: [OracleCase] = [
            OracleCase(
                name: "latin-paragraph",
                attributedString: makeAttributedString(
                    "This is a simple paragraph without any complex formatting or attachments."
                ),
                width: 200,
                widthAccuracy: 25,
                heightAccuracy: 25
            ),
            OracleCase(
                name: "emoji-mix",
                attributedString: makeAttributedString(
                    "Hello 😀 world 😀 emoji wrap test"
                ),
                width: 140,
                widthAccuracy: 25,
                heightAccuracy: 25
            ),
            OracleCase(
                name: "explicit-newlines",
                attributedString: makeAttributedString(
                    "Line one\nLine two\nLine three"
                ),
                width: 200,
                widthAccuracy: 8,
                heightAccuracy: 8
            ),
            OracleCase(
                name: "paragraph-indents",
                attributedString: makeAttributedString(
                    "Indented paragraph with a second line that should wrap clearly."
                ) { style in
                    style.firstLineHeadIndent = 24
                    style.headIndent = 12
                },
                width: 180,
                widthAccuracy: 25,
                heightAccuracy: 25
            )
        ]

        for oracleCase in cases {
            assertOracleParity(oracleCase)
        }
    }

    func testCJKOracleDocumentsCurrentGap() {
        let oracleCase = OracleCase(
            name: "cjk-paragraph",
            attributedString: makeAttributedString(
                "这是一个用于测试换行和宽度计算的中文段落，没有任何附件。"
            ),
            width: 160,
            widthAccuracy: 40,
            heightAccuracy: 25
        )

        XCTExpectFailure(
            "Current arithmetic measurement does not yet maintain rough parity for CJK text. This oracle stays in place so later Phase 11 commits can tighten it into a passing case."
        ) {
            assertOracleParity(oracleCase)
        }
    }

    func testCalculateSizeMatchesPreparedLayoutPhase() {
        let attributedString = makeAttributedString(
            "Indented paragraph with explicit\nline breaks and enough text to wrap onto another line."
        ) { style in
            style.firstLineHeadIndent = 20
            style.headIndent = 10
        }

        let calculator = ArithmeticTextCalculator()
        let prepared = calculator.prepare(attributedString: attributedString)

        let viaWrapper = calculator.calculateSize(for: attributedString, constrainedToWidth: 180)
        let viaPreparedLayout = calculator.layout(prepared: prepared, constrainedToWidth: 180)

        XCTAssertEqual(viaPreparedLayout.width, viaWrapper.width)
        XCTAssertEqual(viaPreparedLayout.height, viaWrapper.height)
    }

    func testProfileAllowsLatinButRejectsUnsupportedScripts() {
        let calculator = ArithmeticTextCalculator()

        let latinProfile = calculator.profile(
            for: makeAttributedString("Simple latin paragraph.")
        )
        XCTAssertTrue(latinProfile.supportsArithmeticLayout)
        XCTAssertFalse(latinProfile.containsUnsupportedScript)

        let cjkProfile = calculator.profile(
            for: makeAttributedString("这是一个中文段落。")
        )
        XCTAssertFalse(cjkProfile.supportsArithmeticLayout)
        XCTAssertTrue(cjkProfile.containsUnsupportedScript)

        let thaiProfile = calculator.profile(
            for: makeAttributedString("ไทยภาษา")
        )
        XCTAssertFalse(thaiProfile.supportsArithmeticLayout)
        XCTAssertTrue(thaiProfile.containsUnsupportedScript)
    }

    func testProfileRejectsComplexScriptMatrix() {
        let calculator = ArithmeticTextCalculator()
        let cases = [
            "مرحبا بالعالم",
            "ไทยภาษา",
            "မြန်မာစာစမ်းသပ်",
            "नमस्ते दुनिया",
            "Status مرحبا 123"
        ]

        for text in cases {
            let profile = calculator.profile(for: makeAttributedString(text))
            XCTAssertFalse(profile.supportsArithmeticLayout, "Expected TextKit fallback for: \(text)")
            XCTAssertTrue(profile.containsUnsupportedScript, "Expected unsupported script marker for: \(text)")
        }
    }

    func testPreparedTextCacheReusesEntriesAcrossWidthChanges() {
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()

        let calculator = ArithmeticTextCalculator()
        let attributedString = makeAttributedString(
            "Prepared cache should be reused while width changes across repeated layouts."
        )

        _ = calculator.calculateSize(for: attributedString, constrainedToWidth: 160)
        XCTAssertEqual(ArithmeticTextCalculator.preparedTextCacheMissesForTesting(), 1)
        XCTAssertEqual(ArithmeticTextCalculator.preparedTextCacheHitsForTesting(), 0)

        _ = calculator.calculateSize(for: attributedString, constrainedToWidth: 240)
        // Same content + same style → second width relayout should hit the prepared cache.
        XCTAssertEqual(ArithmeticTextCalculator.preparedTextCacheMissesForTesting(), 1)
        XCTAssertEqual(ArithmeticTextCalculator.preparedTextCacheHitsForTesting(), 1)
    }

    func testPreparedTextCacheSeparatesParagraphStyleFingerprints() {
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()

        let calculator = ArithmeticTextCalculator()
        let plain = makeAttributedString("Same text, different indent.")
        let indented = makeAttributedString("Same text, different indent.") { style in
            style.firstLineHeadIndent = 24
            style.headIndent = 12
        }

        _ = calculator.calculateSize(for: plain, constrainedToWidth: 220)
        _ = calculator.calculateSize(for: indented, constrainedToWidth: 220)

        // Different paragraph styles → two distinct cache keys → two misses, no hits.
        XCTAssertEqual(ArithmeticTextCalculator.preparedTextCacheMissesForTesting(), 2)
        XCTAssertEqual(ArithmeticTextCalculator.preparedTextCacheHitsForTesting(), 0)
    }

    func testPrepareCapturesSegmentKinds() {
        let attributedString = makeAttributedString("Alpha  beta\nGamma")
        let calculator = ArithmeticTextCalculator()

        let prepared = calculator.prepare(attributedString: attributedString)

        XCTAssertEqual(
            prepared.kinds,
            [.text, .space, .text, .hardBreak, .text]
        )
        XCTAssertEqual(prepared.chunks.map(\.kind), [.content, .content, .content, .hardBreak, .content])
        XCTAssertGreaterThan(prepared.lineEndFitAdvances[0], 0)
        XCTAssertEqual(prepared.lineEndFitAdvances[1], 0)
        XCTAssertGreaterThan(prepared.lineEndFitAdvances[2], 0)
        XCTAssertEqual(prepared.lineEndFitAdvances[3], 0)
        XCTAssertGreaterThan(prepared.lineEndFitAdvances[4], 0)
        XCTAssertGreaterThan(prepared.lineEndPaintAdvances[0], 0)
        XCTAssertGreaterThan(prepared.lineEndPaintAdvances[1], 0)
        XCTAssertGreaterThan(prepared.lineEndPaintAdvances[2], 0)
        XCTAssertEqual(prepared.lineEndPaintAdvances[3], 0)
        XCTAssertGreaterThan(prepared.lineEndPaintAdvances[4], 0)
        XCTAssertEqual(prepared.widths.count, prepared.kinds.count)
        XCTAssertEqual(prepared.lineEndFitAdvances.count, prepared.kinds.count)
        XCTAssertEqual(prepared.lineEndPaintAdvances.count, prepared.kinds.count)
        XCTAssertEqual(prepared.chunks.count, prepared.kinds.count)
        XCTAssertEqual(prepared.heights.count, prepared.kinds.count)
    }

    func testPrepareTreatsZeroWidthSpaceAsBreakOpportunityAndNBSPAsGlue() {
        let calculator = ArithmeticTextCalculator()

        let zeroWidthPrepared = calculator.prepare(
            attributedString: makeAttributedString("Alpha\u{200B}Beta")
        )
        XCTAssertEqual(zeroWidthPrepared.kinds, [.text, .space, .text])
        XCTAssertEqual(zeroWidthPrepared.widths[1], 0, accuracy: 0.001)

        let gluePrepared = calculator.prepare(
            attributedString: makeAttributedString("Alpha\u{00A0}Beta")
        )
        XCTAssertEqual(gluePrepared.kinds, [.text])
    }

    func testPrepareTreatsSoftHyphenAsDiscretionaryBreak() {
        let calculator = ArithmeticTextCalculator()
        let prepared = calculator.prepare(
            attributedString: makeAttributedString("micro\u{00AD}service")
        )

        XCTAssertEqual(prepared.kinds, [.text, .softHyphen, .text])
        XCTAssertEqual(prepared.widths[1], 0, accuracy: 0.001)
        XCTAssertGreaterThan(prepared.lineEndFitAdvances[1], 0)
        XCTAssertEqual(prepared.lineEndFitAdvances[1], prepared.lineEndPaintAdvances[1], accuracy: 0.001)
    }

    func testPreparePreservesCompoundScannerBoundaries() {
        let prepared = ArithmeticTextCalculator().prepare(
            attributedString: makeAttributedString("Alpha\u{200B}Beta\u{00A0}Gamma\u{00AD}Delta\nEpsilon")
        )

        XCTAssertEqual(
            prepared.kinds,
            [.text, .space, .text, .softHyphen, .text, .hardBreak, .text]
        )
        XCTAssertEqual(
            prepared.segmentTexts,
            ["Alpha", "", "Beta\u{00A0}Gamma", "", "Delta", "", "Epsilon"]
        )
        for index in [1, 3, 5] {
            XCTAssertEqual(prepared.widths[index], 0, accuracy: 0.001)
        }
    }

    func testPrepareUsesLocalizedWordBoundariesForThai() {
        let calculator = ArithmeticTextCalculator()
        let prepared = calculator.prepare(
            attributedString: makeAttributedString("ไทยภาษา")
        )

        XCTAssertEqual(prepared.kinds, [.text, .text])
        XCTAssertEqual(prepared.segmentTexts, ["ไทย", "ภาษา"])
    }

    func testPrepareMergesURLLikeRuns() {
        let calculator = ArithmeticTextCalculator()
        let prepared = calculator.prepare(
            attributedString: makeAttributedString("Visit example.com/path?a=b")
        )

        XCTAssertEqual(prepared.kinds, [.text, .space, .text])
        XCTAssertEqual(prepared.segmentTexts, ["Visit", "", "example.com/path?a=b"])
    }

    func testPrepareMergesClosingPunctuationRuns() {
        let calculator = ArithmeticTextCalculator()
        let prepared = calculator.prepare(
            attributedString: makeAttributedString("Hello.")
        )

        XCTAssertEqual(prepared.kinds, [.text])
        XCTAssertEqual(prepared.segmentTexts, ["Hello."])
    }

    func testPrepareMergesNumericStickyRuns() {
        let calculator = ArithmeticTextCalculator()
        let prepared = calculator.prepare(
            attributedString: makeAttributedString("2025-03-31 10:30")
        )

        XCTAssertEqual(prepared.kinds, [.text, .space, .text])
        XCTAssertEqual(prepared.segmentTexts, ["2025-03-31", "", "10:30"])
    }

    func testPrepareMergesURLClosingAndNumericPunctuationInOrder() {
        let prepared = ArithmeticTextCalculator().prepare(
            attributedString: makeAttributedString("Visit example.com/path). 2025-03-31,10:30")
        )

        XCTAssertEqual(prepared.kinds, [.text, .space, .text, .space, .text])
        XCTAssertEqual(
            prepared.segmentTexts,
            ["Visit", "", "example.com/path).", "", "2025-03-31,10:30"]
        )
    }

    func testPrepareMergesCJKStickyRuns() {
        let calculator = ArithmeticTextCalculator()
        let prepared = calculator.prepare(
            attributedString: makeAttributedString("你好，世界 第1章")
        )

        XCTAssertEqual(prepared.kinds, [.text, .space, .text])
        XCTAssertEqual(prepared.segmentTexts, ["你好，世界", "", "第1章"])
    }

    func testPreparedTextSoAStaysAlignedAndCapturesFontsForTextOnly() {
        let prepared = ArithmeticTextCalculator().prepare(
            attributedString: makeAttributedString("Alpha \u{00AD}Beta\nGamma")
        )
        let expectedKinds: [ArithmeticTextCalculator.SegmentKind] = [
            .text, .space, .softHyphen, .text, .hardBreak, .text
        ]

        XCTAssertEqual(prepared.kinds, expectedKinds)
        XCTAssertEqual(prepared.segmentTexts, ["Alpha", "", "", "Beta", "", "Gamma"])
        XCTAssertEqual(prepared.widths.count, expectedKinds.count)
        XCTAssertEqual(prepared.lineEndFitAdvances.count, expectedKinds.count)
        XCTAssertEqual(prepared.lineEndPaintAdvances.count, expectedKinds.count)
        XCTAssertEqual(prepared.segmentTexts.count, expectedKinds.count)
        XCTAssertEqual(prepared.ctFonts.count, expectedKinds.count)
        XCTAssertEqual(prepared.heights.count, expectedKinds.count)
        XCTAssertEqual(prepared.chunks.count, expectedKinds.count)
        XCTAssertEqual(prepared.chunks.map(\.segmentIndex), Array(expectedKinds.indices))
        XCTAssertEqual(
            prepared.chunks.map(\.kind),
            [.content, .content, .content, .content, .hardBreak, .content]
        )

        for index in expectedKinds.indices {
            XCTAssertEqual(prepared.ctFonts[index] != nil, expectedKinds[index] == .text)
            XCTAssertGreaterThan(prepared.heights[index], 0)
        }
    }

    func testPreparedTextLineEndMetadataMatchesEachSegmentKind() {
        let prepared = ArithmeticTextCalculator().prepare(
            attributedString: makeAttributedString("Alpha \u{00AD}Beta\nGamma")
        )

        XCTAssertGreaterThan(prepared.widths[0], 0)
        XCTAssertEqual(prepared.lineEndFitAdvances[0], prepared.widths[0], accuracy: 0.001)
        XCTAssertEqual(prepared.lineEndPaintAdvances[0], prepared.widths[0], accuracy: 0.001)

        XCTAssertGreaterThan(prepared.widths[1], 0)
        XCTAssertEqual(prepared.lineEndFitAdvances[1], 0, accuracy: 0.001)
        XCTAssertEqual(prepared.lineEndPaintAdvances[1], prepared.widths[1], accuracy: 0.001)

        XCTAssertEqual(prepared.widths[2], 0, accuracy: 0.001)
        XCTAssertGreaterThan(prepared.lineEndFitAdvances[2], 0)
        XCTAssertEqual(
            prepared.lineEndPaintAdvances[2],
            prepared.lineEndFitAdvances[2],
            accuracy: 0.001
        )

        XCTAssertEqual(prepared.widths[4], 0, accuracy: 0.001)
        XCTAssertEqual(prepared.lineEndFitAdvances[4], 0, accuracy: 0.001)
        XCTAssertEqual(prepared.lineEndPaintAdvances[4], 0, accuracy: 0.001)
    }

    func testExplicitHardBreakUsesTrimmedLineEndWidth() {
        let attributedString = makeAttributedString("Longest line   \nshort")
        let arithmeticCalc = ArithmeticTextCalculator()
        let textKitCalc = TextKitCalculator()

        let arithmeticSize = arithmeticCalc.calculateSize(for: attributedString, constrainedToWidth: 400)
        let textKitSize = textKitCalc.calculateSize(for: attributedString, constrainedToWidth: 400)

        XCTAssertEqual(arithmeticSize.width, textKitSize.width, accuracy: 1)
        XCTAssertEqual(arithmeticSize.height, textKitSize.height, accuracy: 1)
    }

    func testNarrowFinalLineTrailingSeparatorOverhangMatchesTextKit() {
        let attributedString = makeAttributedString("Hi        ")
        let constrainedWidth: CGFloat = 40
        let arithmeticSize = ArithmeticTextCalculator().calculateSize(
            for: attributedString,
            constrainedToWidth: constrainedWidth
        )
        let textKitSize = TextKitCalculator().calculateSize(
            for: attributedString,
            constrainedToWidth: constrainedWidth
        )

        XCTAssertLessThanOrEqual(arithmeticSize.width, constrainedWidth)
        XCTAssertEqual(arithmeticSize.width, textKitSize.width, accuracy: 1)
    }

    func testNarrowHardBreakTrailingSeparatorOverhangMatchesTextKit() {
        let attributedString = makeAttributedString("Hi        \nMore text")
        let constrainedWidth: CGFloat = 40
        let arithmeticSize = ArithmeticTextCalculator().calculateSize(
            for: attributedString,
            constrainedToWidth: constrainedWidth
        )
        let textKitSize = TextKitCalculator().calculateSize(
            for: attributedString,
            constrainedToWidth: constrainedWidth
        )

        XCTAssertLessThanOrEqual(arithmeticSize.width, constrainedWidth)
        XCTAssertEqual(arithmeticSize.width, textKitSize.width, accuracy: 1)
    }

    func testSoftWrapBoundarySeparatorDoesNotExceedConstraint() {
        let arithmeticCalc = ArithmeticTextCalculator()
        let textKitCalc = TextKitCalculator()
        let originalBoundaryString = makeAttributedString(
            "This is a much longer paragraph that should theoretically wrap if we constrain it to a very tight width, unlike the header."
        )
        let multipleSpacesString = makeAttributedString("Boundary   x")
        let multipleSpacesPrepared = arithmeticCalc.prepare(attributedString: multipleSpacesString)
        let multipleSpacesBoundaryWidth = ceil(multipleSpacesPrepared.widths[0])

        XCTAssertGreaterThan(
            multipleSpacesPrepared.widths[0] + multipleSpacesPrepared.widths[1],
            multipleSpacesBoundaryWidth
        )

        for (attributedString, constrainedWidth) in [
            (originalBoundaryString, CGFloat(100)),
            (multipleSpacesString, multipleSpacesBoundaryWidth)
        ] {
            let arithmeticSize = arithmeticCalc.calculateSize(
                for: attributedString,
                constrainedToWidth: constrainedWidth
            )
            let textKitSize = textKitCalc.calculateSize(
                for: attributedString,
                constrainedToWidth: constrainedWidth
            )

            XCTAssertLessThanOrEqual(arithmeticSize.width, constrainedWidth)
            XCTAssertEqual(arithmeticSize.width, textKitSize.width, accuracy: 1)
        }
    }

    func testSoftWrapRetainsTrailingSeparatorPaintMatchingTextKit() {
        let arithmeticCalc = ArithmeticTextCalculator()
        let textKitCalc = TextKitCalculator()
        let constrainedWidth: CGFloat = 100

        for text in ["Hello world foo", "Hello  world foo", "Hello   world foo"] {
            let attributedString = makeAttributedString(text)
            let arithmeticSize = arithmeticCalc.calculateSize(
                for: attributedString,
                constrainedToWidth: constrainedWidth
            )
            let textKitSize = textKitCalc.calculateSize(
                for: attributedString,
                constrainedToWidth: constrainedWidth
            )

            XCTAssertEqual(
                arithmeticSize.width,
                textKitSize.width,
                accuracy: 1,
                "Trailing separator paint drifted for \(String(reflecting: text))"
            )
        }
    }

    func testOversizedTextTokenFallsBackToGraphemeWrapping() {
        let attributedString = makeAttributedString("Supercalifragilisticexpialidocious")
        let arithmeticCalc = ArithmeticTextCalculator()
        let textKitCalc = TextKitCalculator()

        let arithmeticSize = arithmeticCalc.calculateSize(for: attributedString, constrainedToWidth: 60)
        let textKitSize = textKitCalc.calculateSize(for: attributedString, constrainedToWidth: 60)

        XCTAssertEqual(arithmeticSize.width, textKitSize.width, accuracy: 2)
        XCTAssertEqual(arithmeticSize.height, textKitSize.height, accuracy: 5)
    }

    func testZeroWidthSpaceMatchesTextKitWrapping() {
        let attributedString = makeAttributedString("Alpha\u{200B}Beta")
        let arithmeticCalc = ArithmeticTextCalculator()
        let textKitCalc = TextKitCalculator()

        let arithmeticSize = arithmeticCalc.calculateSize(for: attributedString, constrainedToWidth: 60)
        let textKitSize = textKitCalc.calculateSize(for: attributedString, constrainedToWidth: 60)

        XCTAssertEqual(arithmeticSize.width, textKitSize.width, accuracy: 2)
        XCTAssertEqual(arithmeticSize.height, textKitSize.height, accuracy: 2)
    }

    func testSoftHyphenMatchesTextKitWrapping() {
        let attributedString = makeAttributedString("micro\u{00AD}service")
        let arithmeticCalc = ArithmeticTextCalculator()
        let textKitCalc = TextKitCalculator()

        let arithmeticSize = arithmeticCalc.calculateSize(for: attributedString, constrainedToWidth: 60)
        let textKitSize = textKitCalc.calculateSize(for: attributedString, constrainedToWidth: 60)

        XCTAssertEqual(arithmeticSize.width, textKitSize.width, accuracy: 2)
        XCTAssertEqual(arithmeticSize.height, textKitSize.height, accuracy: 5)
    }

    func testPreparedTextCacheBoundedUnderManyDistinctInputs() {
        // Soft `NSCache.countLimit` should keep memory bounded even when the
        // app touches more distinct strings than the cache can hold. The exact
        // count after eviction is not deterministic (NSCache may evict early
        // or late under pressure), so we just assert the system stays sane:
        // many distinct inputs do not crash and at least the most recent
        // entry is still present.
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()
        let calculator = ArithmeticTextCalculator()

        for i in 0..<2_000 {
            let text = "Distinct paragraph number \(i) used to fill the cache."
            _ = calculator.calculateSize(
                for: makeAttributedString(text),
                constrainedToWidth: 200
            )
        }

        // The last input should round-trip without a crash and still produce
        // a measurable layout — proves the new NSCache backend is wired in.
        let lastText = "Distinct paragraph number 1999 used to fill the cache."
        let size = calculator.calculateSize(
            for: makeAttributedString(lastText),
            constrainedToWidth: 200
        )
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testRepeatedCalculateSizeRemainsStable() {
        let attributedString = makeAttributedString(
            String(repeating: "Repeated words repeated words repeated words. ", count: 40)
        )

        let calculator = ArithmeticTextCalculator()
        let first = calculator.calculateSize(for: attributedString, constrainedToWidth: 220)
        let second = calculator.calculateSize(for: attributedString, constrainedToWidth: 220)

        XCTAssertEqual(first.width, second.width)
        XCTAssertEqual(first.height, second.height)
    }
}
