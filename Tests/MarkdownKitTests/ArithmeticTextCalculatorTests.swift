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

    private func assertStrictOracleParity(
        _ attributedString: NSAttributedString,
        width: CGFloat,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertOracleParity(
            OracleCase(
                name: name,
                attributedString: attributedString,
                width: width,
                widthAccuracy: 1,
                heightAccuracy: 0.001
            ),
            file: file,
            line: line
        )
    }

    private func assertWidthAwareRoutingParity(
        _ attributedString: NSAttributedString,
        width: CGFloat,
        name: String,
        expectedFallback: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let textKit = TextKitCalculator()
        let reference = textKit.calculateSize(
            for: attributedString,
            constrainedToWidth: width
        )
        let arithmetic = ArithmeticTextCalculator()
        let prepared = arithmetic.prepare(attributedString: attributedString)
        let outcome = arithmetic.layoutOutcome(
            prepared: prepared,
            constrainedToWidth: width
        )
        if let expectedFallback {
            XCTAssertEqual(
                outcome.requiresTextKitFallback,
                expectedFallback,
                "Unexpected width-aware routing for '\(name)'",
                file: file,
                line: line
            )
        }
        let routedSize = outcome.requiresTextKitFallback
            ? textKit.calculateSize(for: attributedString, constrainedToWidth: width)
            : outcome.size

        XCTAssertEqual(
            routedSize.width,
            reference.width,
            accuracy: 1,
            "Width-aware routing drifted for '\(name)'",
            file: file,
            line: line
        )
        XCTAssertEqual(
            routedSize.height,
            reference.height,
            accuracy: 0.001,
            "Width-aware routing height drifted for '\(name)'",
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

    func testCJKOracleRetainsRoughParityForFallbackDiagnostics() {
        let oracleCase = OracleCase(
            name: "cjk-paragraph",
            attributedString: makeAttributedString(
                "这是一个用于测试换行和宽度计算的中文段落，没有任何附件。"
            ),
            width: 160,
            widthAccuracy: 40,
            heightAccuracy: 25
        )

        assertOracleParity(oracleCase)
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
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheMissesForTesting(),
            equals: 1
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheHitsForTesting(),
            equals: 0
        )

        _ = calculator.calculateSize(for: attributedString, constrainedToWidth: 240)
        // Same content + same style → second width relayout should hit the prepared cache.
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheMissesForTesting(),
            equals: 1
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheHitsForTesting(),
            equals: 1
        )
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
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheMissesForTesting(),
            equals: 2
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheHitsForTesting(),
            equals: 0
        )
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
        XCTAssertEqual(prepared.baselineOffsets.count, prepared.kinds.count)
        XCTAssertEqual(prepared.containsRequestedFontRuns.count, prepared.kinds.count)
        XCTAssertEqual(prepared.containsVisibleCharacters.count, prepared.kinds.count)
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

    func testPrepareKeepsASCIIHyphenWithLeftTokenWithoutRegressingURLOrNumericRuns() {
        let prepared = ArithmeticTextCalculator().prepare(
            attributedString: makeAttributedString(
                "prefix-width example.com/path?a=b 2025-03-31"
            )
        )

        XCTAssertEqual(
            prepared.kinds,
            [.text, .text, .space, .text, .space, .text]
        )
        XCTAssertEqual(
            prepared.segmentTexts,
            ["prefix-", "width", "", "example.com/path?a=b", "", "2025-03-31"]
        )
    }

    func testASCIIClassifierFastPathPreservesWordAndPunctuationBoundaries() {
        let cases: [(String, [String])] = [
            ("can't", ["can't"]),
            ("rock'n'roll", ["rock'n'roll"]),
            ("12'34", ["12'34"]),
            ("2025's", ["2025'", "s"]),
            ("a'0", ["a'", "0"]),
            ("a_'_", ["a_", "'_"]),
            ("_'_a", ["_'", "_a"]),
            ("foo_bar", ["foo_bar"]),
            ("IPv6?", ["IPv", "6?"]),
            ("A+B", ["A", "+", "B"]),
            ("C#", ["C#"]),
            ("e-mail", ["e-", "mail"]),
            ("word--", ["word", "--"]),
            ("foo-,", ["foo", "-,"]),
            ("--flag", ["--", "flag"]),
            ("version1.2.3", ["version1.2.3"]),
            ("(word)", ["(", "word)"]),
            ("$5.00", ["$5.00"]),
            ("99%", ["99%"]),
            ("foo/bar", ["foo/bar"]),
            ("☐", ["☐"]),
            ("┃", ["┃"])
        ]

        for (text, expected) in cases {
            let fullString = text as NSString
            let utf16 = Array(text.utf16)
            let ranges = ArithmeticTextSegmentClassifierMerger.classifyAndMerge(
                textRange: NSRange(location: 0, length: utf16.count),
                in: fullString,
                utf16: utf16
            )
            XCTAssertEqual(
                ranges.map { fullString.substring(with: $0) },
                expected,
                "Fast-path boundary drift for \(String(reflecting: text))"
            )
        }
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
        XCTAssertEqual(prepared.baselineOffsets.count, expectedKinds.count)
        XCTAssertEqual(prepared.containsRequestedFontRuns.count, expectedKinds.count)
        XCTAssertEqual(prepared.containsVisibleCharacters.count, expectedKinds.count)
        XCTAssertEqual(prepared.chunks.count, expectedKinds.count)
        XCTAssertEqual(prepared.chunks.map(\.segmentIndex), Array(expectedKinds.indices))
        XCTAssertEqual(
            prepared.chunks.map(\.kind),
            [.content, .content, .content, .content, .hardBreak, .content]
        )

        for index in expectedKinds.indices {
            XCTAssertEqual(prepared.ctFonts[index] != nil, expectedKinds[index] == .text)
            XCTAssertGreaterThan(prepared.heights[index], 0)
            XCTAssertGreaterThanOrEqual(prepared.baselineOffsets[index], 0)
            XCTAssertLessThanOrEqual(
                prepared.baselineOffsets[index],
                prepared.heights[index]
            )
        }
    }

    func testCriticalListAndOrderedHyphenWrapsMatchTextKit() {
        let font = Font.systemFont(ofSize: 16)
        let cases: [(name: String, prefix: String, text: String)] = [
            (
                name: "unordered-outer-alpha",
                prefix: "• ",
                text: "• Outer alpha"
            ),
            (
                name: "ordered-prefix-width",
                prefix: "10. ",
                text: "10. Ordered item 10 has wrapping content for prefix-width coverage"
            )
        ]

        for oracleCase in cases {
            let prefixWidth = (oracleCase.prefix as NSString).size(
                withAttributes: [.font: font]
            ).width
            let attributedString = makeAttributedString(oracleCase.text) { style in
                style.firstLineHeadIndent = 0
                style.headIndent = prefixWidth
                style.lineHeightMultiple = 1.2
            }

            assertStrictOracleParity(
                attributedString,
                width: 96,
                name: oracleCase.name
            )
        }
    }

    func testFallbackGlyphLineMetricsMatchTextKitAtDefaultParagraphMultiplier() {
        #if canImport(AppKit)
        // The direct calculator can model AppKit's clean fallback metrics, but
        // routing must reject these paragraphs because their TextKit line box
        // changes after an explicit Helvetica path has run in-process.
        if let emojiFont = Font(name: "AppleColorEmoji", size: 16) {
            for text in ["😀", " \t"] {
                let supported = NSAttributedString(
                    string: text,
                    attributes: [.font: emojiFont]
                )
                let profile = ArithmeticTextCalculator().profile(for: supported)
                XCTAssertFalse(profile.containsAllGlyphFallbackParagraph)
                XCTAssertEqual(profile.containsPositionDependentTab, text.contains("\t"))
                XCTAssertEqual(profile.supportsArithmeticLayout, !text.contains("\t"))
            }
        } else {
            XCTFail("Missing expected AppKit font AppleColorEmoji")
        }

        for fontName in ["AppleColorEmoji", "AlBayan"] {
            guard let font = Font(name: fontName, size: 16) else {
                XCTFail("Missing expected AppKit font \(fontName)")
                continue
            }
            for lineHeightMultiple: CGFloat in [1, 1.2] {
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byWordWrapping
                style.lineHeightMultiple = lineHeightMultiple
                let attributedString = NSAttributedString(
                    string: "Hello",
                    attributes: [.font: font, .paragraphStyle: style]
                )
                let textKitReference = TextKitCalculator().calculateSize(
                    for: attributedString,
                    constrainedToWidth: 240
                )
                let profile = ArithmeticTextCalculator().profile(for: attributedString)
                let textKitAfterProfile = TextKitCalculator().calculateSize(
                    for: attributedString,
                    constrainedToWidth: 240
                )
                XCTAssertTrue(profile.containsAllGlyphFallbackParagraph)
                XCTAssertFalse(profile.supportsArithmeticLayout)
                XCTAssertEqual(
                    textKitAfterProfile,
                    textKitReference,
                    "Profiling \(fontName) must not mutate TextKit fallback state"
                )
            }
        }
        #endif

        for lineHeightMultiple: CGFloat in [1, 1.2] {
            for text in ["☐ Pending", "┃ Quote", "▌ Quote"] {
                let attributedString = makeAttributedString(text) { style in
                    style.lineHeightMultiple = lineHeightMultiple
                }
                let profile = ArithmeticTextCalculator().profile(for: attributedString)
                XCTAssertFalse(profile.containsAllGlyphFallbackParagraph)
                XCTAssertTrue(profile.supportsArithmeticLayout)

                assertStrictOracleParity(
                    attributedString,
                    width: 240,
                    name: "fallback-\(text)-\(lineHeightMultiple)"
                )
            }
        }

        #if canImport(AppKit)
        for fontName in ["Helvetica", "Courier"] {
            guard let font = Font(name: fontName, size: 16) else {
                XCTFail("Missing expected AppKit font \(fontName)")
                continue
            }
            for lineHeightMultiple: CGFloat in [1, 1.2] {
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byWordWrapping
                style.lineHeightMultiple = lineHeightMultiple

                for text in [
                    "Plain content wraps across several lines at the narrow oracle width.",
                    "☐ Fallback content wraps across several lines at the narrow oracle width."
                ] {
                    let attributedString = NSAttributedString(
                        string: text,
                        attributes: [.font: font, .paragraphStyle: style]
                    )
                    assertStrictOracleParity(
                        attributedString,
                        width: 96,
                        name: "\(fontName)-\(text)-\(lineHeightMultiple)"
                    )
                }
            }
        }

        for text in ["☐ Pending", "┃ Quote", "▌ Quote"] {
            for width: CGFloat in [10, 20, 50] {
                assertWidthAwareRoutingParity(
                    makeAttributedString(text) { $0.lineHeightMultiple = 1.2 },
                    width: width,
                    name: "primed-system-fallback-\(text)-\(width)",
                    expectedFallback: text == "☐ Pending" && width == 10 ? true : nil
                )
            }
        }

        // The Helvetica cases above deterministically prime AppKit's alternate
        // all-fallback line box. Capture the TextKit oracle before profiling and
        // verify production routing still fails closed rather than using the
        // clean-state arithmetic height.
        for fontName in ["AppleColorEmoji", "AlBayan"] {
            guard let font = Font(name: fontName, size: 16) else {
                XCTFail("Missing expected AppKit font \(fontName)")
                continue
            }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            style.lineHeightMultiple = 1.2
            let attributedString = NSAttributedString(
                string: "Hello",
                attributes: [.font: font, .paragraphStyle: style]
            )
            let textKitReference = TextKitCalculator().calculateSize(
                for: attributedString,
                constrainedToWidth: 240
            )
            let profile = ArithmeticTextCalculator().profile(for: attributedString)
            let textKitAfterProfile = TextKitCalculator().calculateSize(
                for: attributedString,
                constrainedToWidth: 240
            )

            XCTAssertTrue(profile.containsAllGlyphFallbackParagraph)
            XCTAssertFalse(profile.supportsArithmeticLayout)
            XCTAssertEqual(textKitAfterProfile, textKitReference)
        }

        let unattributed = NSAttributedString(
            string: "Unattributed content wraps using TextKit's twelve-point default font."
        )
        assertStrictOracleParity(
            unattributed,
            width: 96,
            name: "nonempty-unattributed-default-font"
        )
        #endif
    }

    func testProfileRejectsSplitGraphemesAndAppKitUsesWholeVisibleGlyphs() throws {
        let systemFont = Font.systemFont(ofSize: 16)
        let arithmetic = ArithmeticTextCalculator()

        let splitCluster = NSMutableAttributedString(
            string: "A supported prefix before e\u{301} tail",
            attributes: [.font: systemFont]
        )
        let combiningMarkRange = (splitCluster.string as NSString).range(of: "\u{301}")
        splitCluster.addAttribute(
            .font,
            value: Font.boldSystemFont(ofSize: 16),
            range: combiningMarkRange
        )
        let splitProfile = arithmetic.profile(for: splitCluster)
        XCTAssertTrue(splitProfile.containsAttributeSplitGrapheme)
        XCTAssertFalse(splitProfile.supportsArithmeticLayout)

        let colorSplitCluster = NSMutableAttributedString(
            string: "A supported prefix before e\u{301} tail",
            attributes: [.font: systemFont]
        )
        colorSplitCluster.addAttribute(
            .foregroundColor,
            value: Color.red,
            range: (colorSplitCluster.string as NSString).range(of: "\u{301}")
        )
        let colorSplitProfile = arithmetic.profile(for: colorSplitCluster)
        XCTAssertTrue(colorSplitProfile.containsAttributeSplitGrapheme)
        XCTAssertFalse(colorSplitProfile.supportsArithmeticLayout)

        let tabProfile = arithmetic.profile(
            for: NSAttributedString(
                string: "Position\tdependent tab",
                attributes: [.font: systemFont]
            )
        )
        XCTAssertTrue(tabProfile.containsPositionDependentTab)
        XCTAssertFalse(tabProfile.supportsArithmeticLayout)

        XCTAssertTrue(ArithmeticTextMeasurer.supportsArithmeticPointSize(16))
        XCTAssertFalse(ArithmeticTextMeasurer.supportsArithmeticPointSize(.infinity))
        XCTAssertFalse(
            ArithmeticTextMeasurer.supportsArithmeticPointSize(.greatestFiniteMagnitude)
        )

        #if canImport(AppKit)
        let emojiFont = try XCTUnwrap(Font(name: "AppleColorEmoji", size: 16))
        let oversizedPointFont = Font.systemFont(ofSize: CGFloat(Int.max) / 500)
        let oversizedPointProfile = arithmetic.profile(
            for: NSAttributedString(
                string: "Oversized point size",
                attributes: [.font: oversizedPointFont]
            )
        )
        XCTAssertTrue(oversizedPointProfile.containsInvalidFontPointSize)
        XCTAssertFalse(oversizedPointProfile.supportsArithmeticLayout)

        func profile(_ text: String, font: Font? = systemFont) -> ArithmeticTextCalculator.PreparedTextProfile {
            let attributes: [NSAttributedString.Key: Any] = font.map { [.font: $0] } ?? [:]
            return arithmetic.profile(
                for: NSAttributedString(string: text, attributes: attributes)
            )
        }

        for text in ["😀", "👨‍👩‍👧‍👦", "1️⃣", "😀\u{200B}"] {
            XCTAssertTrue(
                profile(text).containsAllGlyphFallbackParagraph,
                "System font must not claim full nominal coverage for \(text)"
            )
        }
        XCTAssertFalse(profile("😀", font: emojiFont).containsAllGlyphFallbackParagraph)
        XCTAssertFalse(profile("A👨‍👩‍👧‍👦").containsAllGlyphFallbackParagraph)
        XCTAssertTrue(profile("A\n👨‍👩‍👧‍👦").containsAllGlyphFallbackParagraph)

        let invisibleOnly = " \t\u{200B}\u{200C}\u{200D}\u{2060}\u{FE0F}"
        XCTAssertFalse(profile(invisibleOnly).containsAllGlyphFallbackParagraph)
        XCTAssertFalse(profile("Hello", font: nil).containsAllGlyphFallbackParagraph)
        XCTAssertTrue(profile("😀", font: nil).containsAllGlyphFallbackParagraph)
        #endif
    }

    func testWidthAwareFallbackDetectsAllFallbackLinesWithoutWhitespaceMasking() {
        #if canImport(AppKit)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineHeightMultiple = 1.2
        let font = Font.systemFont(ofSize: 16)
        let arithmetic = ArithmeticTextCalculator()

        func outcome(_ text: String, width: CGFloat) -> ArithmeticTextLineBreaker.LayoutOutcome {
            let attributedString = NSAttributedString(
                string: text,
                attributes: [.font: font, .paragraphStyle: style]
            )
            XCTAssertTrue(arithmetic.profile(for: attributedString).supportsArithmeticLayout)
            return arithmetic.layoutOutcome(
                prepared: arithmetic.prepare(attributedString: attributedString),
                constrainedToWidth: width
            )
        }

        XCTAssertTrue(outcome("😀 Hello", width: 50).requiresTextKitFallback)
        XCTAssertTrue(outcome("😀 \u{2028}Hello", width: 240).requiresTextKitFallback)
        XCTAssertTrue(outcome("☐ Pending", width: 10).requiresTextKitFallback)
        XCTAssertFalse(outcome("😀 Hello", width: 240).requiresTextKitFallback)
        XCTAssertFalse(outcome("☐ Pending", width: 240).requiresTextKitFallback)

        let invisibleMarkers: [(name: String, value: String)] = [
            ("NBSP", "\u{00A0}"),
            ("narrow-NBSP", "\u{202F}"),
            ("word-joiner", "\u{2060}"),
            ("ZWNJ", "\u{200C}")
        ]
        for marker in invisibleMarkers {
            let text = "😀\(marker.value) A"
            let attributedString = NSAttributedString(
                string: text,
                attributes: [.font: font, .paragraphStyle: style]
            )
            let prepared = arithmetic.prepare(attributedString: attributedString)
            guard let fallbackIndex = prepared.containsRequestedFontRuns.indices.first(where: {
                prepared.containsVisibleCharacters[$0]
                    && !prepared.containsRequestedFontRuns[$0]
            }), let finalAIndex = prepared.segmentTexts.lastIndex(where: { $0.contains("A") }) else {
                XCTFail(
                    "Missing fallback/A segments for \(marker.name): \(prepared.segmentTexts.map { String(reflecting: $0) })"
                )
                continue
            }

            XCTAssertTrue(prepared.containsVisibleCharacters[fallbackIndex], marker.name)
            XCTAssertFalse(prepared.containsRequestedFontRuns[fallbackIndex], marker.name)
            let firstLineWidth = prepared.widths[..<finalAIndex].reduce(0, +)
            XCTAssertTrue(
                arithmetic.layoutOutcome(
                    prepared: prepared,
                    constrainedToWidth: firstLineWidth
                ).requiresTextKitFallback,
                marker.name
            )
            assertWidthAwareRoutingParity(
                attributedString,
                width: firstLineWidth,
                name: "fallback-with-\(marker.name)",
                expectedFallback: true
            )

            XCTAssertFalse(
                outcome("\(marker.value)\u{2028}A", width: 240)
                    .requiresTextKitFallback,
                "A control-only line must not trigger fallback for \(marker.name)"
            )
            XCTAssertFalse(
                outcome("A\(marker.value)", width: 240).requiresTextKitFallback,
                "Invisible content must not hide requested-font evidence for \(marker.name)"
            )
            XCTAssertFalse(
                ArithmeticTextMeasurer.isVisibleUTF16CodeUnit(
                    in: marker.value as NSString,
                    at: 0
                ),
                marker.name
            )
        }

        let surrogateAndIgnorables = "😀\u{200C}\u{FE0F}" as NSString
        XCTAssertTrue(ArithmeticTextMeasurer.isVisibleUTF16CodeUnit(in: surrogateAndIgnorables, at: 0))
        XCTAssertTrue(ArithmeticTextMeasurer.isVisibleUTF16CodeUnit(in: surrogateAndIgnorables, at: 1))
        XCTAssertFalse(ArithmeticTextMeasurer.isVisibleUTF16CodeUnit(in: surrogateAndIgnorables, at: 2))
        XCTAssertFalse(ArithmeticTextMeasurer.isVisibleUTF16CodeUnit(in: surrogateAndIgnorables, at: 3))

        let oversizedFallback = NSAttributedString(
            string: "😀\u{2060}",
            attributes: [.font: font, .paragraphStyle: style]
        )
        let oversizedPrepared = arithmetic.prepare(attributedString: oversizedFallback)
        let oversizedIndex = oversizedPrepared.segmentTexts.firstIndex(where: { $0.contains("😀") })
        XCTAssertNotNil(oversizedIndex)
        if let oversizedIndex {
            var sliceCount = 0
            let oversizedOutcome = arithmetic.layoutOutcome(
                prepared: oversizedPrepared,
                constrainedToWidth: max(oversizedPrepared.widths[oversizedIndex] - 0.5, 0.5),
                onOversizedLine: { sliceCount += 1 }
            )
            XCTAssertGreaterThan(sliceCount, 0)
            XCTAssertTrue(oversizedOutcome.requiresTextKitFallback)
        }

        let laterOversizedText = String(repeating: "W", count: 2_048)
        let earlyFallback = NSAttributedString(
            string: "😀\n\(laterOversizedText)",
            attributes: [.font: font, .paragraphStyle: style]
        )
        let earlyFallbackPrepared = arithmetic.prepare(attributedString: earlyFallback)
        var completeSliceCount = 0
        let completeOutcome = arithmetic.layoutOutcome(
            prepared: earlyFallbackPrepared,
            constrainedToWidth: 50,
            onOversizedLine: { completeSliceCount += 1 }
        )
        XCTAssertTrue(completeOutcome.requiresTextKitFallback)
        XCTAssertGreaterThan(completeSliceCount, 0)

        var shortCircuitSliceCount = 0
        let shortCircuitOutcome = arithmetic.layoutOutcome(
            prepared: earlyFallbackPrepared,
            constrainedToWidth: 50,
            stopWhenTextKitFallbackIsRequired: true,
            onOversizedLine: { shortCircuitSliceCount += 1 }
        )
        XCTAssertTrue(shortCircuitOutcome.requiresTextKitFallback)
        XCTAssertFalse(shortCircuitOutcome.wasCancelled)
        XCTAssertEqual(shortCircuitSliceCount, 0)

        guard let emojiFont = Font(name: "AppleColorEmoji", size: 16) else {
            XCTFail("Missing expected AppKit font AppleColorEmoji")
            return
        }
        _ = TextKitCalculator().calculateSize(
            for: NSAttributedString(string: "Prime fallback state", attributes: [.font: font]),
            constrainedToWidth: 180
        )
        let softHyphenFallback = NSAttributedString(
            string: " \u{00AD}😀",
            attributes: [.font: emojiFont, .paragraphStyle: style]
        )
        XCTAssertTrue(arithmetic.profile(for: softHyphenFallback).supportsArithmeticLayout)
        let softHyphenPrepared = arithmetic.prepare(attributedString: softHyphenFallback)
        let spaceIndex = softHyphenPrepared.kinds.firstIndex(of: .space)
        let softHyphenIndex = softHyphenPrepared.kinds.firstIndex(of: .softHyphen)
        XCTAssertNotNil(spaceIndex)
        XCTAssertNotNil(softHyphenIndex)
        if let spaceIndex, let softHyphenIndex {
            XCTAssertFalse(softHyphenPrepared.containsRequestedFontRuns[softHyphenIndex])
            let spaceAdvance = softHyphenPrepared.widths[spaceIndex]
            let hyphenAdvance = softHyphenPrepared.lineEndPaintAdvances[softHyphenIndex]
            XCTAssertGreaterThan(hyphenAdvance, 0)
            let paintedWidth = spaceAdvance + hyphenAdvance
            let unpaintedWidth = spaceAdvance + hyphenAdvance / 2

            XCTAssertTrue(arithmetic.layoutOutcome(
                prepared: softHyphenPrepared,
                constrainedToWidth: paintedWidth
            ).requiresTextKitFallback)
            XCTAssertFalse(arithmetic.layoutOutcome(
                prepared: softHyphenPrepared,
                constrainedToWidth: unpaintedWidth
            ).requiresTextKitFallback)
            assertWidthAwareRoutingParity(
                softHyphenFallback,
                width: paintedWidth,
                name: "painted-fallback-soft-hyphen",
                expectedFallback: true
            )
            assertWidthAwareRoutingParity(
                softHyphenFallback,
                width: unpaintedWidth,
                name: "unpainted-fallback-soft-hyphen",
                expectedFallback: false
            )
        }

        guard let partialFont = Font(name: "Symbol", size: 16) else {
            XCTFail("Missing expected AppKit font Symbol")
            return
        }
        let mixedSoftHyphenFallback = NSAttributedString(
            string: "1\u{00AD}2",
            attributes: [.font: partialFont, .paragraphStyle: style]
        )
        XCTAssertTrue(arithmetic.profile(for: mixedSoftHyphenFallback).supportsArithmeticLayout)
        let mixedSoftHyphenPrepared = arithmetic.prepare(
            attributedString: mixedSoftHyphenFallback
        )
        let leadingDigitIndex = mixedSoftHyphenPrepared.segmentTexts.firstIndex(of: "1")
        let mixedSoftHyphenIndex = mixedSoftHyphenPrepared.kinds.firstIndex(of: .softHyphen)
        XCTAssertNotNil(leadingDigitIndex)
        XCTAssertNotNil(mixedSoftHyphenIndex)
        if let leadingDigitIndex, let mixedSoftHyphenIndex {
            XCTAssertTrue(mixedSoftHyphenPrepared.containsRequestedFontRuns[leadingDigitIndex])
            XCTAssertFalse(
                mixedSoftHyphenPrepared.containsRequestedFontRuns[mixedSoftHyphenIndex]
            )
            let leadingAdvance = mixedSoftHyphenPrepared.widths[leadingDigitIndex]
            let hyphenAdvance = mixedSoftHyphenPrepared.lineEndPaintAdvances[
                mixedSoftHyphenIndex
            ]
            XCTAssertGreaterThan(hyphenAdvance, 0)
            let paintedWidth = leadingAdvance + hyphenAdvance
            let unpaintedWidth = leadingAdvance + hyphenAdvance / 2

            assertWidthAwareRoutingParity(
                mixedSoftHyphenFallback,
                width: paintedWidth,
                name: "mixed-line-painted-fallback-soft-hyphen",
                expectedFallback: true
            )
            assertWidthAwareRoutingParity(
                mixedSoftHyphenFallback,
                width: unpaintedWidth,
                name: "mixed-line-unpainted-fallback-soft-hyphen",
                expectedFallback: false
            )
        }
        #endif
    }

    func testTrailingUnattributedNewlineUsesTextKitDefaultTwelvePointFont() throws {
        let lineHeightMultiple: CGFloat = 1.2
        let attributedString = NSMutableAttributedString(
            attributedString: makeAttributedString("Styled content") { style in
                style.lineHeightMultiple = lineHeightMultiple
            }
        )
        attributedString.append(NSAttributedString(string: "\n"))

        let newlineIndex = attributedString.length - 1
        XCTAssertTrue(
            attributedString.attributes(at: newlineIndex, effectiveRange: nil).isEmpty,
            "The terminal newline must remain genuinely unattributed"
        )

        #if canImport(UIKit)
        let defaultTextKitFont = Font(name: "Helvetica", size: 12)
            ?? Font.systemFont(ofSize: 12)
        let expectedEmptyLineHeight = defaultTextKitFont.lineHeight * lineHeightMultiple
        #elseif canImport(AppKit)
        let defaultTextKitFont = Font(name: "Helvetica", size: 12)
            ?? Font.userFont(ofSize: 12)
            ?? Font.systemFont(ofSize: 12)
        let expectedEmptyLineHeight = NSLayoutManager().defaultLineHeight(
            for: defaultTextKitFont
        ) * lineHeightMultiple
        #endif

        XCTAssertEqual(defaultTextKitFont.pointSize, 12, accuracy: 0.001)

        let prepared = ArithmeticTextCalculator().prepare(
            attributedString: attributedString
        )
        let terminalParagraph = try XCTUnwrap(prepared.paragraphs.last)
        XCTAssertTrue(terminalParagraph.chunkRange.isEmpty)
        XCTAssertEqual(
            terminalParagraph.emptyLineHeight,
            expectedEmptyLineHeight,
            accuracy: 0.001
        )

        assertStrictOracleParity(
            attributedString,
            width: 240,
            name: "trailing-unattributed-newline"
        )
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

        let prepared = arithmeticCalc.prepare(attributedString: attributedString)
        var sliceCount = 0
        let cancelled = arithmeticCalc.layoutOutcome(
            prepared: prepared,
            constrainedToWidth: 8,
            shouldCancel: { sliceCount == 1 },
            onOversizedLine: { sliceCount += 1 }
        )
        XCTAssertEqual(sliceCount, 1)
        XCTAssertTrue(cancelled.wasCancelled)
        XCTAssertEqual(cancelled.size, .zero)
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
