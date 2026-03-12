import XCTest
@testable import MarkdownKit

final class MathSVGPreprocessorTests: XCTestCase {

    // Typical MathJax output for \frac{a}{b}
    private let sampleSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="2.127ex" height="4.638ex" \
    role="img" focusable="false" viewBox="0 -1342 940 2050" \
    xmlns:xlink="http://www.w3.org/1999/xlink" style="vertical-align: -1.602ex;">\
    <defs><path id="MJX-1" d="M1 2"/></defs>\
    <g fill="currentColor" stroke="currentColor" stroke-width="0">\
    <use xlink:href="#MJX-1"/></g></svg>
    """

    // MARK: - ex → viewBox dimension conversion

    func testConvertsExUnitsToViewBoxDimensions() {
        let result = MathSVGPreprocessor.preprocess(
            svg: sampleSVG, fontXHeight: 8.1, textColor: nil
        )

        // Should replace ex units with viewBox dimensions (940, 2050)
        XCTAssertTrue(result.svg.contains("width=\"940\""), "width should be viewBox width")
        XCTAssertTrue(result.svg.contains("height=\"2050\""), "height should be viewBox height")
        XCTAssertFalse(result.svg.contains("ex\""), "no ex units should remain")
    }

    func testComputesCorrectPointSize() {
        let fontXHeight: CGFloat = 8.1
        let result = MathSVGPreprocessor.preprocess(
            svg: sampleSVG, fontXHeight: fontXHeight, textColor: nil
        )

        // 2.127ex * 8.1 ≈ 17.23, 4.638ex * 8.1 ≈ 37.57
        XCTAssertEqual(result.size.width, 2.127 * fontXHeight, accuracy: 0.01)
        XCTAssertEqual(result.size.height, 4.638 * fontXHeight, accuracy: 0.01)
    }

    // MARK: - currentColor replacement

    func testReplacesCurrentColorWithHex() {
        let result = MathSVGPreprocessor.preprocess(
            svg: sampleSVG, fontXHeight: 8.1, textColor: "#FF0000"
        )

        XCTAssertFalse(result.svg.contains("currentColor"))
        XCTAssertTrue(result.svg.contains("#FF0000"))
    }

    func testPreservesCurrentColorWhenNoTextColor() {
        let result = MathSVGPreprocessor.preprocess(
            svg: sampleSVG, fontXHeight: 8.1, textColor: nil
        )

        XCTAssertTrue(result.svg.contains("currentColor"))
    }

    // MARK: - style attribute removal

    func testStripsStyleAttribute() {
        let result = MathSVGPreprocessor.preprocess(
            svg: sampleSVG, fontXHeight: 8.1, textColor: nil
        )

        XCTAssertFalse(result.svg.contains("style="))
        XCTAssertFalse(result.svg.contains("vertical-align"))
    }

    // MARK: - SVG structure preservation

    func testPreservesViewBox() {
        let result = MathSVGPreprocessor.preprocess(
            svg: sampleSVG, fontXHeight: 8.1, textColor: nil
        )

        XCTAssertTrue(result.svg.contains("viewBox=\"0 -1342 940 2050\""))
    }

    func testPreservesDefs() {
        let result = MathSVGPreprocessor.preprocess(
            svg: sampleSVG, fontXHeight: 8.1, textColor: nil
        )

        XCTAssertTrue(result.svg.contains("<defs>"))
        XCTAssertTrue(result.svg.contains("MJX-1"))
    }

    // MARK: - Edge cases

    func testHandlesSVGWithoutExUnits() {
        let svg = """
        <svg width="100" height="50" viewBox="0 0 100 50"><rect/></svg>
        """
        let result = MathSVGPreprocessor.preprocess(
            svg: svg, fontXHeight: 8.1, textColor: "#000"
        )

        // Size should be zero since no ex units to convert
        XCTAssertEqual(result.size.width, 0)
        XCTAssertEqual(result.size.height, 0)
    }

    func testHandlesSVGWithoutViewBox() {
        let svg = """
        <svg width="2.0ex" height="3.0ex"><rect fill="currentColor"/></svg>
        """
        let result = MathSVGPreprocessor.preprocess(
            svg: svg, fontXHeight: 10.0, textColor: "#000"
        )

        // Should still compute point size from ex units
        XCTAssertEqual(result.size.width, 20.0, accuracy: 0.01)
        XCTAssertEqual(result.size.height, 30.0, accuracy: 0.01)
        // Without viewBox, ex values stay (can't replace with viewBox dims)
        // The ex values remain since there's no viewBox to use
    }
}
