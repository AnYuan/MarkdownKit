import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class ArithmeticParagraphModelTests: XCTestCase {

    private struct RunSpec {
        let range: NSRange
        let fontSize: CGFloat
        let paragraphStyle: NSParagraphStyle
    }

    private func makeParagraphStyle(
        firstLineHeadIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        paragraphSpacingBefore: CGFloat = 0,
        paragraphSpacing: CGFloat = 0,
        lineHeightMultiple: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.firstLineHeadIndent = firstLineHeadIndent
        style.headIndent = headIndent
        style.paragraphSpacingBefore = paragraphSpacingBefore
        style.paragraphSpacing = paragraphSpacing
        style.lineHeightMultiple = lineHeightMultiple
        return style.copy() as! NSParagraphStyle
    }

    private func makeAttributedString(_ string: String, runs: [RunSpec]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: string)
        for run in runs {
            attributed.addAttributes([
                .font: Font.systemFont(ofSize: run.fontSize),
                .paragraphStyle: run.paragraphStyle
            ], range: run.range)
        }
        return attributed
    }

    private func lineHeight(fontSize: CGFloat, lineHeightMultiple: CGFloat = 0) -> CGFloat {
        let font = Font.systemFont(ofSize: fontSize)
        #if canImport(UIKit)
        let base = font.lineHeight
        #elseif canImport(AppKit)
        let base = NSLayoutManager().defaultLineHeight(for: font)
        #endif
        return base * (lineHeightMultiple > 0 ? lineHeightMultiple : 1)
    }

    private func hardBreakIndices(in prepared: ArithmeticTextCalculator.PreparedText) -> [Int] {
        prepared.chunks.indices.filter { prepared.chunks[$0].kind == .hardBreak }
    }

    private func assertTextKitOracle(
        attributedString: NSAttributedString,
        prepared: ArithmeticTextCalculator.PreparedText,
        width: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let calculator = ArithmeticTextCalculator()
        let preparedSize = calculator.layout(prepared: prepared, constrainedToWidth: width)
        let wrapperSize = calculator.calculateSize(for: attributedString, constrainedToWidth: width)
        let oracleSize = TextKitCalculator().calculateSize(for: attributedString, constrainedToWidth: width)

        XCTAssertEqual(preparedSize.width, wrapperSize.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(preparedSize.height, wrapperSize.height, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(
            preparedSize.width,
            oracleSize.width,
            accuracy: 1,
            "Width drift at constraint \(width): arithmetic=\(preparedSize), TextKit=\(oracleSize)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            preparedSize.height,
            oracleSize.height,
            accuracy: 0.001,
            "Height drift at constraint \(width): arithmetic=\(preparedSize), TextKit=\(oracleSize)",
            file: file,
            line: line
        )
    }

    func testWrappedParagraphsResetIndentAndPreserveSpacingContracts() throws {
        let firstParagraph = "First paragraph wraps with enough words to occupy multiple lines.\n"
        let secondParagraph = "Second paragraph also wraps differently and still occupies multiple lines."
        let firstStyle = makeParagraphStyle(
            firstLineHeadIndent: 28,
            headIndent: 12,
            paragraphSpacing: 6,
            lineHeightMultiple: 1.15
        )
        let secondStyle = makeParagraphStyle(
            firstLineHeadIndent: 18,
            headIndent: 6,
            paragraphSpacingBefore: 8,
            paragraphSpacing: 14,
            lineHeightMultiple: 1.35
        )
        let attributedString = makeAttributedString(
            firstParagraph + secondParagraph,
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: (firstParagraph as NSString).length),
                    fontSize: 16,
                    paragraphStyle: firstStyle
                ),
                RunSpec(
                    range: NSRange(
                        location: (firstParagraph as NSString).length,
                        length: (secondParagraph as NSString).length
                    ),
                    fontSize: 16,
                    paragraphStyle: secondStyle
                )
            ]
        )

        let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)
        let hardBreaks = hardBreakIndices(in: prepared)
        XCTAssertEqual(hardBreaks.count, 1)
        let breakIndex = try XCTUnwrap(hardBreaks.first)

        XCTAssertEqual(prepared.paragraphs.count, 2)
        XCTAssertEqual(prepared.paragraphs[0].chunkRange, 0..<(breakIndex + 1))
        XCTAssertEqual(prepared.paragraphs[1].chunkRange, (breakIndex + 1)..<prepared.chunks.count)
        XCTAssertEqual(prepared.paragraphs[0].firstLineHeadIndent, 28, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[0].headIndent, 12, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[0].paragraphSpacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[0].paragraphSpacingAfter, 6, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[1].firstLineHeadIndent, 18, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[1].headIndent, 6, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[1].paragraphSpacingBefore, 8, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[1].paragraphSpacingAfter, 0, accuracy: 0.001)

        assertTextKitOracle(attributedString: attributedString, prepared: prepared, width: 150)
    }

    func testCRLFProducesSingleHardBreakChunk() throws {
        let text = "A\r\nB"
        let style = makeParagraphStyle(firstLineHeadIndent: 22, headIndent: 8, lineHeightMultiple: 1.2)
        let attributedString = makeAttributedString(
            text,
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: (text as NSString).length),
                    fontSize: 16,
                    paragraphStyle: style
                )
            ]
        )

        let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)
        let hardBreaks = hardBreakIndices(in: prepared)

        XCTAssertEqual(prepared.kinds.filter { $0 == .hardBreak }.count, 1)
        XCTAssertEqual(hardBreaks.count, 1)
        let breakIndex = try XCTUnwrap(hardBreaks.first)
        XCTAssertEqual(prepared.paragraphs.count, 2)
        XCTAssertEqual(prepared.paragraphs[0].chunkRange, 0..<(breakIndex + 1))
        XCTAssertEqual(prepared.paragraphs[1].chunkRange, (breakIndex + 1)..<prepared.chunks.count)

        assertTextKitOracle(attributedString: attributedString, prepared: prepared, width: 120)
    }

    func testSeparatorFontOnlySuppliesEmptyLineHeight() {
        let style = makeParagraphStyle()
        let cases: [(String, [RunSpec])] = [
            (
                "A\nB",
                [
                    RunSpec(range: NSRange(location: 0, length: 1), fontSize: 16, paragraphStyle: style),
                    RunSpec(range: NSRange(location: 1, length: 1), fontSize: 40, paragraphStyle: style),
                    RunSpec(range: NSRange(location: 2, length: 1), fontSize: 16, paragraphStyle: style)
                ]
            ),
            (
                "A\n",
                [
                    RunSpec(range: NSRange(location: 0, length: 1), fontSize: 16, paragraphStyle: style),
                    RunSpec(range: NSRange(location: 1, length: 1), fontSize: 40, paragraphStyle: style)
                ]
            ),
            (
                "\nB",
                [
                    RunSpec(range: NSRange(location: 0, length: 1), fontSize: 40, paragraphStyle: style),
                    RunSpec(range: NSRange(location: 1, length: 1), fontSize: 16, paragraphStyle: style)
                ]
            ),
            (
                "A\u{2028}B",
                [
                    RunSpec(range: NSRange(location: 0, length: 1), fontSize: 16, paragraphStyle: style),
                    RunSpec(range: NSRange(location: 1, length: 1), fontSize: 40, paragraphStyle: style),
                    RunSpec(range: NSRange(location: 2, length: 1), fontSize: 16, paragraphStyle: style)
                ]
            )
        ]

        for (text, runs) in cases {
            let attributedString = makeAttributedString(text, runs: runs)
            let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)
            assertTextKitOracle(attributedString: attributedString, prepared: prepared, width: 200)
        }

        #if canImport(AppKit)
        let lowerFontSize: CGFloat = 16.0323
        let upperFontSize: CGFloat = 16.0324
        let lowerLineHeight = lineHeight(fontSize: lowerFontSize)
        let upperLineHeight = lineHeight(fontSize: upperFontSize)
        XCTAssertNotEqual(lowerLineHeight, upperLineHeight)

        let subMillipointAttributedString = makeAttributedString(
            "A\nB",
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: 2),
                    fontSize: lowerFontSize,
                    paragraphStyle: style
                ),
                RunSpec(
                    range: NSRange(location: 2, length: 1),
                    fontSize: upperFontSize,
                    paragraphStyle: style
                )
            ]
        )
        let subMillipointPrepared = ArithmeticTextMeasurer.prepare(
            attributedString: subMillipointAttributedString
        )

        XCTAssertEqual(
            subMillipointPrepared.paragraphs[0].emptyLineHeight,
            lowerLineHeight,
            accuracy: 0.001
        )
        XCTAssertEqual(
            subMillipointPrepared.paragraphs[1].emptyLineHeight,
            upperLineHeight,
            accuracy: 0.001
        )
        assertTextKitOracle(
            attributedString: subMillipointAttributedString,
            prepared: subMillipointPrepared,
            width: 200
        )

        let lowerFontAttributedString = makeAttributedString(
            "A",
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: 1),
                    fontSize: lowerFontSize,
                    paragraphStyle: style
                )
            ]
        )
        let upperFontAttributedString = makeAttributedString(
            "A",
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: 1),
                    fontSize: upperFontSize,
                    paragraphStyle: style
                )
            ]
        )
        let calculator = ArithmeticTextCalculator()
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()

        let lowerFontPrepared = calculator.prepare(attributedString: lowerFontAttributedString)
        let upperFontPrepared = calculator.prepare(attributedString: upperFontAttributedString)
        _ = calculator.prepare(attributedString: lowerFontAttributedString)
        _ = calculator.prepare(attributedString: upperFontAttributedString)

        XCTAssertEqual(
            lowerFontPrepared.paragraphs[0].emptyLineHeight,
            lowerLineHeight,
            accuracy: 0.001
        )
        XCTAssertEqual(
            upperFontPrepared.paragraphs[0].emptyLineHeight,
            upperLineHeight,
            accuracy: 0.001
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheMissesForTesting(),
            equals: 2,
            "Sub-millipoint fonts with distinct line heights must not share prepared payloads"
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheHitsForTesting(),
            equals: 2,
            "Each exact font size should reuse only its own prepared payload"
        )
        #endif
    }

    func testTrailingCRLFUsesCRForEmptyBoundaryAndLFFontForTerminalLine() {
        let style = makeParagraphStyle()
        let trailingAttributedString = makeAttributedString(
            "A\r\n",
            runs: [
                RunSpec(range: NSRange(location: 0, length: 1), fontSize: 16, paragraphStyle: style),
                RunSpec(range: NSRange(location: 1, length: 1), fontSize: 30, paragraphStyle: style),
                RunSpec(range: NSRange(location: 2, length: 1), fontSize: 40, paragraphStyle: style)
            ]
        )
        let trailingPrepared = ArithmeticTextCalculator().prepare(
            attributedString: trailingAttributedString
        )

        XCTAssertEqual(trailingPrepared.paragraphs.count, 2)
        XCTAssertEqual(
            trailingPrepared.paragraphs[1].emptyLineHeight,
            lineHeight(fontSize: 40),
            accuracy: 0.001
        )
        assertTextKitOracle(
            attributedString: trailingAttributedString,
            prepared: trailingPrepared,
            width: 200
        )

        let leadingAttributedString = makeAttributedString(
            "\r\nB",
            runs: [
                RunSpec(range: NSRange(location: 0, length: 1), fontSize: 30, paragraphStyle: style),
                RunSpec(range: NSRange(location: 1, length: 1), fontSize: 40, paragraphStyle: style),
                RunSpec(range: NSRange(location: 2, length: 1), fontSize: 16, paragraphStyle: style)
            ]
        )
        let leadingPrepared = ArithmeticTextCalculator().prepare(
            attributedString: leadingAttributedString
        )
        let firstBreak = try? XCTUnwrap(hardBreakIndices(in: leadingPrepared).first)
        if let firstBreak {
            let breakSegment = leadingPrepared.chunks[firstBreak].segmentIndex
            XCTAssertEqual(leadingPrepared.heights[breakSegment], lineHeight(fontSize: 30), accuracy: 0.001)
        }
        assertTextKitOracle(
            attributedString: leadingAttributedString,
            prepared: leadingPrepared,
            width: 200
        )
    }

    func testTerminalParagraphInheritsResolvedStyleButUsesFinalSeparatorFont() {
        let contentStyle = makeParagraphStyle(
            firstLineHeadIndent: 10,
            headIndent: 10,
            paragraphSpacingBefore: 9,
            paragraphSpacing: 5,
            lineHeightMultiple: 1.5
        )
        let separatorStyle = makeParagraphStyle(
            firstLineHeadIndent: 80,
            headIndent: 80,
            paragraphSpacingBefore: 30,
            paragraphSpacing: 40,
            lineHeightMultiple: 0.5
        )
        let attributedString = makeAttributedString(
            "A\n",
            runs: [
                RunSpec(range: NSRange(location: 0, length: 1), fontSize: 16, paragraphStyle: contentStyle),
                RunSpec(range: NSRange(location: 1, length: 1), fontSize: 30, paragraphStyle: separatorStyle)
            ]
        )
        let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)

        XCTAssertEqual(prepared.paragraphs.count, 2)
        XCTAssertEqual(prepared.paragraphs[1].firstLineHeadIndent, 10, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[1].headIndent, 10, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[1].paragraphSpacingBefore, 9, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[1].paragraphSpacingAfter, 0, accuracy: 0.001)
        XCTAssertEqual(
            prepared.paragraphs[1].emptyLineHeight,
            lineHeight(fontSize: 30, lineHeightMultiple: 1.5),
            accuracy: 0.001
        )
        assertTextKitOracle(attributedString: attributedString, prepared: prepared, width: 200)
    }

    func testTrailingSoftHyphenRemainsInvisibleAtParagraphEnds() {
        let style = makeParagraphStyle()
        for text in ["micro\u{00AD}", "micro\u{00AD}\n", "micro\u{00AD}\r\n", "micro\u{00AD}\u{2028}"] {
            let attributedString = makeAttributedString(
                text,
                runs: [
                    RunSpec(
                        range: NSRange(location: 0, length: (text as NSString).length),
                        fontSize: 16,
                        paragraphStyle: style
                    )
                ]
            )
            let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)

            for width: CGFloat in [41, 200] {
                assertTextKitOracle(
                    attributedString: attributedString,
                    prepared: prepared,
                    width: width
                )
            }
        }
    }

    func testSoftHyphenPaintsOnlyForATakenFittingBreak() {
        let style = makeParagraphStyle()
        let text = "micro\u{00AD}service"
        let attributedString = makeAttributedString(
            text,
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: (text as NSString).length),
                    fontSize: 16,
                    paragraphStyle: style
                )
            ]
        )
        let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)

        for width: CGFloat in [35, 41, 42, 47, 47.5, 47.75, 48, 60, 200] {
            assertTextKitOracle(
                attributedString: attributedString,
                prepared: prepared,
                width: width
            )
        }
    }

    func testLineSeparatorStaysWithinParagraphWhileParagraphSeparatorResetsIt() {
        let style = makeParagraphStyle(
            firstLineHeadIndent: 20,
            headIndent: 10,
            paragraphSpacingBefore: 7,
            paragraphSpacing: 8
        )

        let lineSeparatorString = makeAttributedString(
            "A\u{2028}B",
            runs: [
                RunSpec(range: NSRange(location: 0, length: 3), fontSize: 16, paragraphStyle: style)
            ]
        )
        let lineSeparatorPrepared = ArithmeticTextCalculator().prepare(
            attributedString: lineSeparatorString
        )
        XCTAssertEqual(lineSeparatorPrepared.paragraphs.count, 1)
        XCTAssertEqual(hardBreakIndices(in: lineSeparatorPrepared).count, 1)
        XCTAssertEqual(
            lineSeparatorPrepared.paragraphs[0].chunkRange,
            0..<lineSeparatorPrepared.chunks.count
        )
        assertTextKitOracle(
            attributedString: lineSeparatorString,
            prepared: lineSeparatorPrepared,
            width: 120
        )

        for trailingLineSeparatorText in ["A\u{2028}", "\u{2028}"] {
            let trailingLineSeparatorString = makeAttributedString(
                trailingLineSeparatorText,
                runs: [
                    RunSpec(
                        range: NSRange(
                            location: 0,
                            length: (trailingLineSeparatorText as NSString).length
                        ),
                        fontSize: 16,
                        paragraphStyle: style
                    )
                ]
            )
            let trailingLineSeparatorPrepared = ArithmeticTextCalculator().prepare(
                attributedString: trailingLineSeparatorString
            )
            XCTAssertEqual(trailingLineSeparatorPrepared.paragraphs.count, 1)
            assertTextKitOracle(
                attributedString: trailingLineSeparatorString,
                prepared: trailingLineSeparatorPrepared,
                width: 120
            )
        }

        let paragraphSeparatorString = makeAttributedString(
            "A\u{2029}B",
            runs: [
                RunSpec(range: NSRange(location: 0, length: 3), fontSize: 16, paragraphStyle: style)
            ]
        )
        let paragraphSeparatorPrepared = ArithmeticTextCalculator().prepare(
            attributedString: paragraphSeparatorString
        )
        XCTAssertEqual(paragraphSeparatorPrepared.paragraphs.count, 2)
        XCTAssertEqual(hardBreakIndices(in: paragraphSeparatorPrepared).count, 1)
        assertTextKitOracle(
            attributedString: paragraphSeparatorString,
            prepared: paragraphSeparatorPrepared,
            width: 120
        )
    }

    func testFirstParagraphIgnoresSpacingBeforeAndTrailingEmptyParagraphReceivesIt() {
        let style = makeParagraphStyle(paragraphSpacingBefore: 9, paragraphSpacing: 5)

        let singleParagraph = makeAttributedString(
            "A",
            runs: [
                RunSpec(range: NSRange(location: 0, length: 1), fontSize: 16, paragraphStyle: style)
            ]
        )
        let singlePrepared = ArithmeticTextCalculator().prepare(attributedString: singleParagraph)
        XCTAssertEqual(singlePrepared.paragraphs[0].paragraphSpacingBefore, 9, accuracy: 0.001)
        assertTextKitOracle(
            attributedString: singleParagraph,
            prepared: singlePrepared,
            width: 120
        )

        let trailingSeparator = makeAttributedString(
            "A\n",
            runs: [
                RunSpec(range: NSRange(location: 0, length: 2), fontSize: 16, paragraphStyle: style)
            ]
        )
        let trailingPrepared = ArithmeticTextCalculator().prepare(attributedString: trailingSeparator)
        XCTAssertEqual(trailingPrepared.paragraphs.count, 2)
        XCTAssertEqual(trailingPrepared.paragraphs[1].paragraphSpacingBefore, 9, accuracy: 0.001)
        assertTextKitOracle(
            attributedString: trailingSeparator,
            prepared: trailingPrepared,
            width: 120
        )
    }

    func testTrailingSeparatorsCreateTerminalEmptyParagraphWithoutExtraSpacing() {
        let style = makeParagraphStyle(paragraphSpacing: 12, lineHeightMultiple: 1.25)

        for text in ["\n", "A\n"] {
            let attributedString = makeAttributedString(
                text,
                runs: [
                    RunSpec(
                        range: NSRange(location: 0, length: (text as NSString).length),
                        fontSize: 16,
                        paragraphStyle: style
                    )
                ]
            )
            let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)
            let hardBreaks = hardBreakIndices(in: prepared)
            guard let hardBreak = hardBreaks.first else {
                XCTFail("Expected one hard break for \(String(reflecting: text))")
                continue
            }

            XCTAssertEqual(prepared.paragraphs.count, 2, text)
            XCTAssertEqual(hardBreaks.count, 1, text)
            XCTAssertEqual(prepared.paragraphs[0].chunkRange.upperBound, hardBreak + 1, text)
            XCTAssertTrue(prepared.paragraphs[1].chunkRange.isEmpty, text)
            XCTAssertEqual(prepared.paragraphs[1].chunkRange.lowerBound, hardBreak + 1, text)
            XCTAssertEqual(prepared.paragraphs[0].paragraphSpacingAfter, 12, accuracy: 0.001, text)
            XCTAssertEqual(prepared.paragraphs[1].paragraphSpacingAfter, 0, accuracy: 0.001, text)
            XCTAssertEqual(
                prepared.paragraphs[1].emptyLineHeight,
                lineHeight(fontSize: 16, lineHeightMultiple: 1.25),
                accuracy: 0.001,
                text
            )

            assertTextKitOracle(attributedString: attributedString, prepared: prepared, width: 120)
        }
    }

    func testEmptyMiddleParagraphUsesItsOwnStyledLineBox() {
        let text = "A\n\nB"
        let firstParagraph = NSRange(location: 0, length: 2)
        let middleParagraph = NSRange(location: 2, length: 1)
        let finalParagraph = NSRange(location: 3, length: 1)
        let firstStyle = makeParagraphStyle(
            firstLineHeadIndent: 20,
            headIndent: 20,
            lineHeightMultiple: 1.0
        )
        let middleStyle = makeParagraphStyle(
            firstLineHeadIndent: 0,
            headIndent: 0,
            lineHeightMultiple: 1.4
        )
        let finalStyle = makeParagraphStyle(
            firstLineHeadIndent: 30,
            headIndent: 30,
            lineHeightMultiple: 1.0
        )
        let attributedString = makeAttributedString(
            text,
            runs: [
                RunSpec(range: firstParagraph, fontSize: 16, paragraphStyle: firstStyle),
                RunSpec(range: middleParagraph, fontSize: 24, paragraphStyle: middleStyle),
                RunSpec(range: finalParagraph, fontSize: 16, paragraphStyle: finalStyle)
            ]
        )

        let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)
        let hardBreaks = hardBreakIndices(in: prepared)
        guard hardBreaks.count == 2 else {
            XCTFail("Expected two hard breaks for \(String(reflecting: text))")
            return
        }

        XCTAssertEqual(hardBreaks.count, 2)
        XCTAssertEqual(prepared.paragraphs.count, 3)
        XCTAssertEqual(prepared.paragraphs[1].chunkRange, (hardBreaks[0] + 1)..<(hardBreaks[1] + 1))
        XCTAssertEqual(
            prepared.paragraphs[1].emptyLineHeight,
            lineHeight(fontSize: 24, lineHeightMultiple: 1.4),
            accuracy: 0.001
        )

        assertTextKitOracle(attributedString: attributedString, prepared: prepared, width: 160)
    }

    func testLeadingParagraphStyleWinsAcrossMidParagraphStyleChangeAndMixedFontsMatchTextKit() {
        let lead = "Lead words "
        let emphasis = "BIG emphasis wraps onto the next line"
        let leadingStyle = makeParagraphStyle(
            firstLineHeadIndent: 26,
            headIndent: 10,
            lineHeightMultiple: 1.5
        )
        let trailingStyle = makeParagraphStyle(
            firstLineHeadIndent: 2,
            headIndent: 1,
            lineHeightMultiple: 0.8
        )
        let attributedString = makeAttributedString(
            lead + emphasis,
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: (lead as NSString).length),
                    fontSize: 16,
                    paragraphStyle: leadingStyle
                ),
                RunSpec(
                    range: NSRange(
                        location: (lead as NSString).length,
                        length: (emphasis as NSString).length
                    ),
                    fontSize: 24,
                    paragraphStyle: trailingStyle
                )
            ]
        )

        let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)

        XCTAssertEqual(prepared.paragraphs.count, 1)
        XCTAssertEqual(prepared.paragraphs[0].chunkRange, 0..<prepared.chunks.count)
        XCTAssertEqual(prepared.paragraphs[0].firstLineHeadIndent, 26, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[0].headIndent, 10, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[0].paragraphSpacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(prepared.paragraphs[0].paragraphSpacingAfter, 0, accuracy: 0.001)

        assertTextKitOracle(attributedString: attributedString, prepared: prepared, width: 170)
    }

    func testPreparedTextCacheSeparatesParagraphSpacingBeforeFromParagraphSpacingAfter() {
        let firstParagraph = "Cache key spacing contract\n"
        let secondParagraph = "Tail"
        let text = firstParagraph + secondParagraph
        let plainStyle = makeParagraphStyle()
        let afterStyle = makeParagraphStyle(paragraphSpacing: 9)
        let beforeStyle = makeParagraphStyle(paragraphSpacingBefore: 9)
        let plainAttributedString = makeAttributedString(
            text,
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: (firstParagraph as NSString).length),
                    fontSize: 16,
                    paragraphStyle: plainStyle
                ),
                RunSpec(
                    range: NSRange(
                        location: (firstParagraph as NSString).length,
                        length: (secondParagraph as NSString).length
                    ),
                    fontSize: 16,
                    paragraphStyle: plainStyle
                )
            ]
        )
        let afterAttributedString = makeAttributedString(
            text,
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: (firstParagraph as NSString).length),
                    fontSize: 16,
                    paragraphStyle: afterStyle
                ),
                RunSpec(
                    range: NSRange(
                        location: (firstParagraph as NSString).length,
                        length: (secondParagraph as NSString).length
                    ),
                    fontSize: 16,
                    paragraphStyle: plainStyle
                )
            ]
        )
        let beforeAttributedString = makeAttributedString(
            text,
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: (firstParagraph as NSString).length),
                    fontSize: 16,
                    paragraphStyle: plainStyle
                ),
                RunSpec(
                    range: NSRange(
                        location: (firstParagraph as NSString).length,
                        length: (secondParagraph as NSString).length
                    ),
                    fontSize: 16,
                    paragraphStyle: beforeStyle
                )
            ]
        )

        let calculator = ArithmeticTextCalculator()
        let plainPrepared = calculator.prepare(attributedString: plainAttributedString)
        let afterPrepared = calculator.prepare(attributedString: afterAttributedString)
        let beforePrepared = calculator.prepare(attributedString: beforeAttributedString)

        XCTAssertEqual(plainPrepared.paragraphs.count, 2)
        XCTAssertEqual(plainPrepared.paragraphs[0].paragraphSpacingAfter, 0, accuracy: 0.001)
        XCTAssertEqual(plainPrepared.paragraphs[1].paragraphSpacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(afterPrepared.paragraphs.count, 2)
        XCTAssertEqual(afterPrepared.paragraphs[0].paragraphSpacingAfter, 9, accuracy: 0.001)
        XCTAssertEqual(beforePrepared.paragraphs.count, 2)
        XCTAssertEqual(beforePrepared.paragraphs[1].paragraphSpacingBefore, 9, accuracy: 0.001)

        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()

        let width: CGFloat = 220
        let plainFirstSize = calculator.calculateSize(for: plainAttributedString, constrainedToWidth: width)
        let afterFirstSize = calculator.calculateSize(for: afterAttributedString, constrainedToWidth: width)
        let beforeSize = calculator.calculateSize(for: beforeAttributedString, constrainedToWidth: width)
        let plainSecondSize = calculator.calculateSize(for: plainAttributedString, constrainedToWidth: width)
        let afterSecondSize = calculator.calculateSize(for: afterAttributedString, constrainedToWidth: width)
        let beforeSecondSize = calculator.calculateSize(for: beforeAttributedString, constrainedToWidth: width)
        let plainOracle = TextKitCalculator().calculateSize(for: plainAttributedString, constrainedToWidth: width)
        let afterOracle = TextKitCalculator().calculateSize(for: afterAttributedString, constrainedToWidth: width)
        let beforeOracle = TextKitCalculator().calculateSize(for: beforeAttributedString, constrainedToWidth: width)

        XCTAssertEqual(plainFirstSize.width, plainOracle.width, accuracy: 1)
        XCTAssertEqual(plainFirstSize.height, plainOracle.height, accuracy: 1)
        XCTAssertEqual(afterFirstSize.width, afterOracle.width, accuracy: 1)
        XCTAssertEqual(afterFirstSize.height, afterOracle.height, accuracy: 1)
        XCTAssertEqual(beforeSize.width, beforeOracle.width, accuracy: 1)
        XCTAssertEqual(beforeSize.height, beforeOracle.height, accuracy: 1)
        XCTAssertEqual(plainSecondSize, plainFirstSize)
        XCTAssertEqual(afterSecondSize.width, afterOracle.width, accuracy: 1)
        XCTAssertEqual(afterSecondSize.height, afterOracle.height, accuracy: 1)
        XCTAssertEqual(beforeSecondSize, beforeSize)
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheMissesForTesting(),
            equals: 3,
            "Plain, paragraphSpacing, and paragraphSpacingBefore must each have a distinct cache key"
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheHitsForTesting(),
            equals: 3,
            "Each repeated paragraph-spacing variant should reuse its own prepared-text cache entry"
        )
    }

    func testPreparedTextCacheKeepsSubMillipointParagraphMetricsDistinct() {
        let text = "A\nB"
        let firstStyle = makeParagraphStyle(paragraphSpacing: 0.00040)
        let secondStyle = makeParagraphStyle(paragraphSpacing: 0.00049)
        let tailStyle = makeParagraphStyle()

        func attributedString(firstParagraphStyle: NSParagraphStyle) -> NSAttributedString {
            makeAttributedString(
                text,
                runs: [
                    RunSpec(
                        range: NSRange(location: 0, length: 2),
                        fontSize: 16,
                        paragraphStyle: firstParagraphStyle
                    ),
                    RunSpec(
                        range: NSRange(location: 2, length: 1),
                        fontSize: 16,
                        paragraphStyle: tailStyle
                    )
                ]
            )
        }

        let first = attributedString(firstParagraphStyle: firstStyle)
        let second = attributedString(firstParagraphStyle: secondStyle)
        let calculator = ArithmeticTextCalculator()
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()

        let firstPrepared = calculator.prepare(attributedString: first)
        let secondPrepared = calculator.prepare(attributedString: second)
        _ = calculator.prepare(attributedString: first)
        _ = calculator.prepare(attributedString: second)

        XCTAssertEqual(firstPrepared.paragraphs[0].paragraphSpacingAfter, 0.00040)
        XCTAssertEqual(secondPrepared.paragraphs[0].paragraphSpacingAfter, 0.00049)
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheMissesForTesting(),
            equals: 2,
            "Sub-millipoint paragraph metrics must not collide in the prepared-text cache"
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheHitsForTesting(),
            equals: 2,
            "Each exact paragraph metric should reuse only its own prepared-text entry"
        )
    }

    func testNonFiniteParagraphMetricsDoNotTrapOrProduceNonFiniteLayout() {
        let style = makeParagraphStyle(
            firstLineHeadIndent: .infinity,
            headIndent: .nan,
            paragraphSpacingBefore: .infinity,
            paragraphSpacing: .nan,
            lineHeightMultiple: .infinity
        )
        let text = "Non-finite paragraph metrics"
        let attributedString = makeAttributedString(
            text,
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: (text as NSString).length),
                    fontSize: 16,
                    paragraphStyle: style
                )
            ]
        )

        let size = ArithmeticTextCalculator().calculateSize(
            for: attributedString,
            constrainedToWidth: 180
        )

        XCTAssertTrue(size.width.isFinite)
        XCTAssertTrue(size.height.isFinite)
    }

    func testLargeFiniteParagraphMetricsSaturateToFiniteGeometry() {
        let style = makeParagraphStyle(
            paragraphSpacingBefore: .greatestFiniteMagnitude,
            paragraphSpacing: .greatestFiniteMagnitude,
            lineHeightMultiple: .greatestFiniteMagnitude
        )
        let text = "A\nB"
        let attributedString = makeAttributedString(
            text,
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: (text as NSString).length),
                    fontSize: 16,
                    paragraphStyle: style
                )
            ]
        )

        let size = ArithmeticTextCalculator().calculateSize(
            for: attributedString,
            constrainedToWidth: 180
        )

        XCTAssertTrue(size.width.isFinite)
        XCTAssertTrue(size.height.isFinite)
        XCTAssertGreaterThanOrEqual(size.width, 0)
        XCTAssertGreaterThanOrEqual(size.height, 0)
        XCTAssertLessThanOrEqual(size.width, CGFloat(Int32.max))
        XCTAssertLessThanOrEqual(size.height, CGFloat(Int32.max))
    }

    func testNegativeParagraphMetricsClampToTextKitLayout() {
        let style = makeParagraphStyle(
            firstLineHeadIndent: -30,
            headIndent: -20,
            paragraphSpacingBefore: -9,
            paragraphSpacing: -7
        )
        let text = "First paragraph wraps across lines at this width.\nSecond paragraph also wraps."
        let attributedString = makeAttributedString(
            text,
            runs: [
                RunSpec(
                    range: NSRange(location: 0, length: (text as NSString).length),
                    fontSize: 16,
                    paragraphStyle: style
                )
            ]
        )
        let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)

        for paragraph in prepared.paragraphs {
            XCTAssertEqual(paragraph.firstLineHeadIndent, 0)
            XCTAssertEqual(paragraph.headIndent, 0)
            XCTAssertEqual(paragraph.paragraphSpacingBefore, 0)
            XCTAssertEqual(paragraph.paragraphSpacingAfter, 0)
        }
        assertTextKitOracle(attributedString: attributedString, prepared: prepared, width: 140)
    }

    func testFractionalLineHeightRoundsUpLikeTextKit() {
        let style = makeParagraphStyle(lineHeightMultiple: 1.15)
        let attributedString = makeAttributedString(
            "A",
            runs: [
                RunSpec(range: NSRange(location: 0, length: 1), fontSize: 16, paragraphStyle: style)
            ]
        )
        let arithmeticSize = ArithmeticTextCalculator().calculateSize(
            for: attributedString,
            constrainedToWidth: 200
        )
        let textKitSize = TextKitCalculator().calculateSize(
            for: attributedString,
            constrainedToWidth: 200
        )

        XCTAssertEqual(arithmeticSize.height, textKitSize.height, accuracy: 0.001)
    }

    func testOversizedTokenClipsWithinPerParagraphIndent() {
        let firstParagraph = "Short\n"
        let secondParagraph = "WW"
        let firstStyle = makeParagraphStyle()
        for (firstLineIndent, headIndent): (CGFloat, CGFloat) in [
            (119, 119),
            (120, 120),
            (121, 121),
            (120, 0)
        ] {
            let secondStyle = makeParagraphStyle(
                firstLineHeadIndent: firstLineIndent,
                headIndent: headIndent
            )
            let attributedString = makeAttributedString(
                firstParagraph + secondParagraph,
                runs: [
                    RunSpec(
                        range: NSRange(location: 0, length: (firstParagraph as NSString).length),
                        fontSize: 16,
                        paragraphStyle: firstStyle
                    ),
                    RunSpec(
                        range: NSRange(
                            location: (firstParagraph as NSString).length,
                            length: (secondParagraph as NSString).length
                        ),
                        fontSize: 16,
                        paragraphStyle: secondStyle
                    )
                ]
            )
            let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)
            let arithmeticSize = ArithmeticTextCalculator().layout(
                prepared: prepared,
                constrainedToWidth: 120
            )

            XCTAssertLessThanOrEqual(arithmeticSize.width, 120)
            assertTextKitOracle(attributedString: attributedString, prepared: prepared, width: 120)
        }
    }

    func testUsedRectHeightExcludesLeadingInvisibleLineFragments() {
        let fullyIndentedStyle = makeParagraphStyle(firstLineHeadIndent: 120, headIndent: 120)
        let recoverAfterFirstLineStyle = makeParagraphStyle(firstLineHeadIndent: 120, headIndent: 0)
        let cases: [(String, NSParagraphStyle)] = [
            ("WW", recoverAfterFirstLineStyle),
            ("A\n", fullyIndentedStyle),
            ("A\u{2028}", fullyIndentedStyle)
        ]

        for (text, style) in cases {
            let attributedString = makeAttributedString(
                text,
                runs: [
                    RunSpec(
                        range: NSRange(location: 0, length: (text as NSString).length),
                        fontSize: 16,
                        paragraphStyle: style
                    )
                ]
            )
            let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)
            assertTextKitOracle(attributedString: attributedString, prepared: prepared, width: 120)
        }
    }

    func testTerminalEmptyParagraphContributesItsZeroWidthIndentToUsedRect() {
        let firstParagraph = "Short\n"
        let secondParagraph = "A\n"

        for indent: CGFloat in [120, 121] {
            let attributedString = makeAttributedString(
                firstParagraph + secondParagraph,
                runs: [
                    RunSpec(
                        range: NSRange(location: 0, length: (firstParagraph as NSString).length),
                        fontSize: 16,
                        paragraphStyle: makeParagraphStyle()
                    ),
                    RunSpec(
                        range: NSRange(
                            location: (firstParagraph as NSString).length,
                            length: (secondParagraph as NSString).length
                        ),
                        fontSize: 16,
                        paragraphStyle: makeParagraphStyle(
                            firstLineHeadIndent: indent,
                            headIndent: indent
                        )
                    )
                ]
            )
            let prepared = ArithmeticTextCalculator().prepare(attributedString: attributedString)
            assertTextKitOracle(attributedString: attributedString, prepared: prepared, width: 120)
        }
    }
}
