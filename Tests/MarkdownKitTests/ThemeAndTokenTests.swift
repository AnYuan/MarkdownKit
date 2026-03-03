import XCTest
@testable import MarkdownKit

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
        XCTAssertEqual(theme.typography.header1.font.pointSize, 32)
        XCTAssertEqual(theme.typography.header2.font.pointSize, 24)
        XCTAssertEqual(theme.typography.header3.font.pointSize, 20)
        XCTAssertEqual(theme.typography.paragraph.font.pointSize, 16)
        XCTAssertEqual(theme.typography.codeBlock.font.pointSize, 14)
        XCTAssertNotEqual(theme.colors.inlineCodeColor.background, .clear)
    }

    func testCustomThemeInitialization() {
        let theme = Theme(
            typography: Theme.Typography(
                header1: TypographyToken(font: Font.systemFont(ofSize: 40)),
                header2: TypographyToken(font: Font.systemFont(ofSize: 30)),
                header3: TypographyToken(font: Font.systemFont(ofSize: 22)),
                paragraph: TypographyToken(font: Font.systemFont(ofSize: 18)),
                codeBlock: TypographyToken(font: Font.monospacedSystemFont(ofSize: 16, weight: .regular))
            ),
            colors: Theme.Colors(
                textColor: ColorToken(foreground: .white),
                codeColor: ColorToken(foreground: .green, background: .black),
                tableColor: ColorToken(foreground: .gray, background: .darkGray)
            )
        )

        XCTAssertEqual(theme.typography.header1.font.pointSize, 40)
        XCTAssertEqual(theme.typography.codeBlock.font.pointSize, 16)
        XCTAssertEqual(theme.colors.textColor.foreground, .white)
        XCTAssertEqual(theme.colors.codeColor.background, .black)
        XCTAssertEqual(theme.colors.inlineCodeColor.background, .black)
    }

    func testCustomInlineCodeColorOverridesCodeColor() {
        let inlineCodeToken = ColorToken(foreground: .black, background: .yellow)
        let theme = Theme(
            typography: Theme.Typography(
                header1: TypographyToken(font: Font.systemFont(ofSize: 32)),
                header2: TypographyToken(font: Font.systemFont(ofSize: 24)),
                header3: TypographyToken(font: Font.systemFont(ofSize: 20)),
                paragraph: TypographyToken(font: Font.systemFont(ofSize: 16)),
                codeBlock: TypographyToken(font: Font.monospacedSystemFont(ofSize: 14, weight: .regular))
            ),
            colors: Theme.Colors(
                textColor: ColorToken(foreground: .white),
                codeColor: ColorToken(foreground: .green, background: .black),
                inlineCodeColor: inlineCodeToken,
                tableColor: ColorToken(foreground: .gray, background: .darkGray)
            )
        )

        XCTAssertEqual(theme.colors.codeColor.background, .black)
        XCTAssertEqual(theme.colors.inlineCodeColor.foreground, .black)
        XCTAssertEqual(theme.colors.inlineCodeColor.background, .yellow)
    }

    func testCustomThemeFlowsThroughLayoutSolver() async throws {
        let customFont = Font.boldSystemFont(ofSize: 48)
        let theme = Theme(
            typography: Theme.Typography(
                header1: TypographyToken(font: customFont),
                header2: TypographyToken(font: Font.systemFont(ofSize: 24)),
                header3: TypographyToken(font: Font.systemFont(ofSize: 20)),
                paragraph: TypographyToken(font: Font.systemFont(ofSize: 16)),
                codeBlock: TypographyToken(font: Font.monospacedSystemFont(ofSize: 14, weight: .regular))
            ),
            colors: Theme.Colors(
                textColor: ColorToken(foreground: .red),
                codeColor: ColorToken(foreground: .green, background: .black),
                tableColor: ColorToken(foreground: .gray, background: .darkGray)
            )
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
