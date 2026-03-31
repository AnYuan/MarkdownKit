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

    func testPrepareMergesCJKStickyRuns() {
        let calculator = ArithmeticTextCalculator()
        let prepared = calculator.prepare(
            attributedString: makeAttributedString("你好，世界 第1章")
        )

        XCTAssertEqual(prepared.kinds, [.text, .space, .text])
        XCTAssertEqual(prepared.segmentTexts, ["你好，世界", "", "第1章"])
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
