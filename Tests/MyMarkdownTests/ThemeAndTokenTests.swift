import XCTest
@testable import MyMarkdown

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class ThemeAndTokenTests: XCTestCase {

    // MARK: - TypographyToken

    func testTypographyTokenDefaultValues() {
        let token = TypographyToken(font: Font.systemFont(ofSize: 16))
        XCTAssertEqual(token.lineHeightMultiple, 1.2)
        XCTAssertEqual(token.paragraphSpacing, 16.0)
    }

    func testTypographyTokenCustomValues() {
        let font = Font.boldSystemFont(ofSize: 24)
        let token = TypographyToken(font: font, lineHeightMultiple: 1.5, paragraphSpacing: 8.0)
        XCTAssertEqual(token.font, font)
        XCTAssertEqual(token.lineHeightMultiple, 1.5)
        XCTAssertEqual(token.paragraphSpacing, 8.0)
    }

    // MARK: - ColorToken

    func testColorTokenDefaultBackground() {
        let token = ColorToken(foreground: .red)
        XCTAssertEqual(token.foreground, .red)
        XCTAssertEqual(token.background, .clear)
    }

    func testColorTokenCustomBackground() {
        let token = ColorToken(foreground: .white, background: .black)
        XCTAssertEqual(token.foreground, .white)
        XCTAssertEqual(token.background, .black)
    }

    // MARK: - Theme

    func testDefaultThemeInitialization() {
        let theme = Theme.default
        XCTAssertEqual(theme.header1.font.pointSize, 32)
        XCTAssertEqual(theme.header2.font.pointSize, 24)
        XCTAssertEqual(theme.header3.font.pointSize, 20)
        XCTAssertEqual(theme.paragraph.font.pointSize, 16)
        XCTAssertEqual(theme.codeBlock.font.pointSize, 14)
    }

    func testCustomThemeInitialization() {
        let theme = Theme(
            header1: TypographyToken(font: Font.systemFont(ofSize: 40)),
            header2: TypographyToken(font: Font.systemFont(ofSize: 30)),
            header3: TypographyToken(font: Font.systemFont(ofSize: 22)),
            paragraph: TypographyToken(font: Font.systemFont(ofSize: 18)),
            codeBlock: TypographyToken(font: Font.monospacedSystemFont(ofSize: 16, weight: .regular)),
            textColor: ColorToken(foreground: .white),
            codeColor: ColorToken(foreground: .green, background: .black),
            tableColor: ColorToken(foreground: .gray, background: .darkGray)
        )

        XCTAssertEqual(theme.header1.font.pointSize, 40)
        XCTAssertEqual(theme.codeBlock.font.pointSize, 16)
        XCTAssertEqual(theme.textColor.foreground, .white)
        XCTAssertEqual(theme.codeColor.background, .black)
    }

    func testCustomThemeFlowsThroughLayoutSolver() async throws {
        let customFont = Font.boldSystemFont(ofSize: 48)
        let theme = Theme(
            header1: TypographyToken(font: customFont),
            header2: TypographyToken(font: Font.systemFont(ofSize: 24)),
            header3: TypographyToken(font: Font.systemFont(ofSize: 20)),
            paragraph: TypographyToken(font: Font.systemFont(ofSize: 16)),
            codeBlock: TypographyToken(font: Font.monospacedSystemFont(ofSize: 14, weight: .regular)),
            textColor: ColorToken(foreground: .red),
            codeColor: ColorToken(foreground: .green, background: .black),
            tableColor: ColorToken(foreground: .gray, background: .darkGray)
        )

        let layout = await TestHelper.solveLayout("# Big Header", theme: theme)
        let headerLayout = layout.children[0]

        guard let attrStr = headerLayout.attributedString else {
            XCTFail("Header layout missing attributed string")
            return
        }
        var foundFont: Font?
        attrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            if let font = value as? Font { foundFont = font }
        }
        XCTAssertEqual(foundFont?.pointSize, 48)
    }
}
