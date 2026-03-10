import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class ThemeCustomizationTests: XCTestCase {

    // MARK: - Sub-struct Default Values

    func testCodeBlockStyleDefaults() {
        let style = Theme.CodeBlockStyle()
        XCTAssertEqual(style.cornerRadius, 8)
        XCTAssertEqual(style.layoutTotalInset, 16)
        XCTAssertEqual(style.viewPadding, 16)
        XCTAssertEqual(style.labelParagraphSpacing, 6)
        XCTAssertEqual(style.inlineCodeFontSizeRatio, 0.92)
        XCTAssertEqual(style.inlineCodeMinFontSize, 11)
        XCTAssertEqual(style.copyButtonSize, 30)
        XCTAssertEqual(style.copyButtonCornerRadius, 6)
        XCTAssertEqual(style.copyButtonMargin, 8)
        XCTAssertEqual(style.copyButtonIconSize, 14)
        XCTAssertEqual(style.macOSCornerRadius, 6)
        XCTAssertEqual(style.macOSTextContainerInset, CGSize(width: 8, height: 8))
    }

    func testBlockQuoteStyleDefaults() {
        let style = Theme.BlockQuoteStyle()
        XCTAssertEqual(style.indent, 16)
        XCTAssertEqual(style.barCharacter, "┃ ")
    }

    func testListStyleDefaults() {
        let style = Theme.ListStyle()
        XCTAssertEqual(style.bulletCharacter, "• ")
        XCTAssertEqual(style.checkedCharacter, "☑ ")
        XCTAssertEqual(style.uncheckedCharacter, "☐ ")
        XCTAssertEqual(style.nestedIndentDelta, 16)
    }

    func testDetailsStyleDefaults() {
        let style = Theme.DetailsStyle()
        XCTAssertEqual(style.openDisclosure, "▼ ")
        XCTAssertEqual(style.closedDisclosure, "▶ ")
    }

    func testTableStyleDefaults() {
        let style = Theme.TableStyle()
        XCTAssertEqual(style.cornerRadius, 8)
        XCTAssertEqual(style.borderWidth, 1)
        XCTAssertEqual(style.cellPaddingH, 12)
        XCTAssertEqual(style.cellPaddingV, 8)
        XCTAssertEqual(style.dividerHeight, 0.5)
        XCTAssertEqual(style.fontSize, 13)
        XCTAssertEqual(style.uiKitHorizontalInset, 8)
        XCTAssertEqual(style.appKitHorizontalPadding, 16)
        XCTAssertEqual(style.appKitBorderAllowance, 2)
        XCTAssertEqual(style.minimumReadableColumnWidth, 36)
        XCTAssertEqual(style.cellParagraphSpacing, 2)
        XCTAssertEqual(style.narrowFallbackMaxChars, 12)
        XCTAssertEqual(style.alternatingRowAlpha, 0.45)
        XCTAssertEqual(style.separatorAlpha, 0.55)
    }

    func testHighlightStyleDefaults() {
        let style = Theme.HighlightStyle()
        XCTAssertEqual(style.cornerRadius, 3)
        XCTAssertEqual(style.darkModeAlpha, 0.22)
        XCTAssertEqual(style.lightModeAlpha, 0.11)
        XCTAssertEqual(style.insetDX, -2)
        XCTAssertEqual(style.insetDY, -1)
        XCTAssertEqual(style.fadeInDuration, 0.1)
        XCTAssertEqual(style.fadeOutDuration, 0.15)
    }

    func testThematicBreakStyleDefaults() {
        let style = Theme.ThematicBreakStyle()
        XCTAssertEqual(style.paddingTop, 16)
        XCTAssertEqual(style.paddingBottom, 24)
        XCTAssertEqual(style.dividerHeight, 0.5)
    }

    // MARK: - Default Theme Preserves All Defaults

    func testDefaultThemeHasDefaultSubstructs() {
        let theme = Theme.default
        XCTAssertEqual(theme.codeBlock, Theme.CodeBlockStyle())
        XCTAssertEqual(theme.blockQuote, Theme.BlockQuoteStyle())
        XCTAssertEqual(theme.list, Theme.ListStyle())
        XCTAssertEqual(theme.details, Theme.DetailsStyle())
        XCTAssertEqual(theme.table, Theme.TableStyle())
        XCTAssertEqual(theme.highlight, Theme.HighlightStyle())
        XCTAssertEqual(theme.thematicBreak, Theme.ThematicBreakStyle())
    }

    // MARK: - Custom Values Propagate to Layout Output

    func testCustomBulletCharacterPropagates() async throws {
        let theme = makeTheme(list: Theme.ListStyle(bulletCharacter: "→ "))
        let layout = await TestHelper.solveLayout("- Item one\n- Item two", theme: theme)
        guard let attrStr = layout.children.first?.attributedString else {
            XCTFail("Missing attributed string"); return
        }
        XCTAssertTrue(attrStr.string.contains("→"), "Custom bullet character should appear in output")
        XCTAssertFalse(attrStr.string.contains("•"), "Default bullet should not appear")
    }

    func testCustomCheckboxCharactersPropagates() async throws {
        let theme = makeTheme(list: Theme.ListStyle(checkedCharacter: "[x] ", uncheckedCharacter: "[ ] "))
        let layout = await TestHelper.solveLayout("- [x] Done\n- [ ] Todo", theme: theme)
        guard let attrStr = layout.children.first?.attributedString else {
            XCTFail("Missing attributed string"); return
        }
        XCTAssertTrue(attrStr.string.contains("[x]"), "Custom checked character should appear")
        XCTAssertTrue(attrStr.string.contains("[ ]"), "Custom unchecked character should appear")
    }

    func testCustomBlockQuoteBarPropagates() async throws {
        let theme = makeTheme(blockQuote: Theme.BlockQuoteStyle(barCharacter: "| "))
        let layout = await TestHelper.solveLayout("> Quote text", theme: theme)
        guard let attrStr = layout.children.first?.attributedString else {
            XCTFail("Missing attributed string"); return
        }
        XCTAssertTrue(attrStr.string.hasPrefix("| "), "Custom bar character should appear: got '\(attrStr.string)'")
    }

    func testCustomBlockQuoteIndentPropagates() async throws {
        let theme = makeTheme(blockQuote: Theme.BlockQuoteStyle(indent: 32))
        let layout = await TestHelper.solveLayout("> Indented quote", theme: theme)
        guard let attrStr = layout.children.first?.attributedString else {
            XCTFail("Missing attributed string"); return
        }
        var foundIndent: CGFloat = 0
        attrStr.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            if let para = value as? NSParagraphStyle {
                foundIndent = max(foundIndent, para.headIndent)
            }
        }
        XCTAssertEqual(foundIndent, 32, "Custom indent should propagate to paragraph style")
    }

    func testCustomInlineCodeFontRatioPropagates() async throws {
        let theme = makeTheme(codeBlock: Theme.CodeBlockStyle(inlineCodeFontSizeRatio: 0.8, inlineCodeMinFontSize: 8))
        let layout = await TestHelper.solveLayout("text `code` text", theme: theme)
        guard let attrStr = layout.children.first?.attributedString else {
            XCTFail("Missing attributed string"); return
        }
        // The paragraph font is 16pt, so inline code should be max(8, 16*0.8) = 12.8pt
        var foundCodeFont: Font?
        attrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            if let font = value as? Font, font.fontDescriptor.symbolicTraits.contains(Font.isMonospacedTrait) {
                foundCodeFont = font
            }
        }
        XCTAssertNotNil(foundCodeFont, "Should find monospaced font for inline code")
        if let size = foundCodeFont?.pointSize {
            XCTAssertEqual(Double(size), 12.8, accuracy: 0.1)
        }
    }

    func testCustomLabelParagraphSpacingPropagates() async throws {
        let theme = makeTheme(codeBlock: Theme.CodeBlockStyle(labelParagraphSpacing: 12))
        let layout = await TestHelper.solveLayout("```swift\nlet x = 1\n```", theme: theme)
        guard let attrStr = layout.children.first?.attributedString else {
            XCTFail("Missing attributed string"); return
        }
        // The label is the first line; check its paragraph spacing
        var foundSpacing: CGFloat = 0
        if attrStr.length > 0 {
            if let para = attrStr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                foundSpacing = para.paragraphSpacing
            }
        }
        XCTAssertEqual(foundSpacing, 12, "Custom label paragraph spacing should propagate")
    }

    // MARK: - Backward Compatibility

    func testExistingInitStillCompiles() {
        // This test verifies that the old two-parameter init still works
        let theme = Theme(
            typography: Theme.default.typography,
            colors: Theme.default.colors
        )
        // All new sub-configs should be defaults
        XCTAssertEqual(theme.codeBlock, Theme.CodeBlockStyle())
        XCTAssertEqual(theme.list, Theme.ListStyle())
    }

    // MARK: - Helpers

    private func makeTheme(
        codeBlock: Theme.CodeBlockStyle = Theme.CodeBlockStyle(),
        blockQuote: Theme.BlockQuoteStyle = Theme.BlockQuoteStyle(),
        list: Theme.ListStyle = Theme.ListStyle(),
        details: Theme.DetailsStyle = Theme.DetailsStyle(),
        table: Theme.TableStyle = Theme.TableStyle(),
        syntaxColors: Theme.SyntaxColors = Theme.SyntaxColors(),
        highlight: Theme.HighlightStyle = Theme.HighlightStyle(),
        thematicBreak: Theme.ThematicBreakStyle = Theme.ThematicBreakStyle()
    ) -> Theme {
        Theme(
            typography: Theme.default.typography,
            colors: Theme.default.colors,
            codeBlock: codeBlock,
            blockQuote: blockQuote,
            list: list,
            details: details,
            table: table,
            syntaxColors: syntaxColors,
            highlight: highlight,
            thematicBreak: thematicBreak
        )
    }
}

// MARK: - Platform-specific font trait check

private extension Font {
    #if canImport(UIKit)
    static let isMonospacedTrait: UIFontDescriptor.SymbolicTraits = .traitMonoSpace
    #elseif canImport(AppKit)
    static let isMonospacedTrait: NSFontDescriptor.SymbolicTraits = .monoSpace
    #endif
}
