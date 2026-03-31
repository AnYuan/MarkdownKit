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
        XCTAssertEqual(prepared.widths.count, prepared.kinds.count)
        XCTAssertEqual(prepared.heights.count, prepared.kinds.count)
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
