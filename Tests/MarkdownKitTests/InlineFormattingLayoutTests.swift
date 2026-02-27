import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class InlineFormattingLayoutTests: XCTestCase {

    // MARK: - Bold / Italic / Strikethrough Layout

    func testStrongNodeLayoutAppliesBoldFont() async throws {
        let layout = await TestHelper.solveLayout("**bold text**")
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string for bold paragraph")
            return
        }

        var foundBold = false
        attrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            guard let font = value as? Font else { return }
            #if canImport(UIKit)
            if font.fontDescriptor.symbolicTraits.contains(.traitBold) { foundBold = true }
            #elseif canImport(AppKit)
            if NSFontManager.shared.traits(of: font).contains(.boldFontMask) { foundBold = true }
            #endif
        }
        XCTAssertTrue(foundBold, "Bold text should produce a font with bold trait")
    }

    func testEmphasisNodeLayoutAppliesItalicFont() async throws {
        let layout = await TestHelper.solveLayout("*italic text*")
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string for italic paragraph")
            return
        }

        var foundItalic = false
        attrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            guard let font = value as? Font else { return }
            #if canImport(UIKit)
            if font.fontDescriptor.symbolicTraits.contains(.traitItalic) { foundItalic = true }
            #elseif canImport(AppKit)
            if NSFontManager.shared.traits(of: font).contains(.italicFontMask) { foundItalic = true }
            #endif
        }
        XCTAssertTrue(foundItalic, "Italic text should produce a font with italic trait")
    }

    func testStrikethroughNodeLayoutAppliesStrikethroughAttribute() async throws {
        let layout = await TestHelper.solveLayout("~~struck~~")
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string for strikethrough paragraph")
            return
        }

        var foundStrikethrough = false
        attrStr.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            if let style = value as? Int, style == NSUnderlineStyle.single.rawValue {
                foundStrikethrough = true
            }
        }
        XCTAssertTrue(foundStrikethrough, "Strikethrough text should have .strikethroughStyle attribute")
    }

    // MARK: - Block Quote Layout

    func testBlockQuoteLayoutAppliesIndentAndQuoteBar() async throws {
        let layout = await TestHelper.solveLayout("> Quoted text")
        let bqLayout = layout.children[0]

        guard let attrStr = bqLayout.attributedString else {
            XCTFail("Expected attributed string for block quote")
            return
        }

        let text = attrStr.string
        XCTAssertTrue(text.contains("┃"), "Block quote should contain vertical bar character ┃")
        XCTAssertTrue(text.contains("Quoted text"), "Block quote should contain the quoted text")

        // Verify indentation via paragraph style
        var foundIndent = false
        attrStr.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            if style.headIndent >= 16 { foundIndent = true }
        }
        XCTAssertTrue(foundIndent, "Block quote should have headIndent >= 16")

        // Verify gray foreground color on body text
        var foundGray = false
        attrStr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            guard let color = value as? Color else { return }
            if color == Color.gray { foundGray = true }
        }
        XCTAssertTrue(foundGray, "Block quote text should use gray foreground color")
    }

    func testBlockQuoteBarUsesBlueColor() async throws {
        let layout = await TestHelper.solveLayout("> Text")
        let bqLayout = layout.children[0]

        guard let attrStr = bqLayout.attributedString else {
            XCTFail("Expected attributed string for block quote")
            return
        }

        // Find the "┃" character and check its color
        var foundBlue = false
        attrStr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attrStr.length)) { value, range, _ in
            let substring = (attrStr.string as NSString).substring(with: range)
            if substring.contains("┃"), let color = value as? Color, color == Color.systemBlue {
                foundBlue = true
            }
        }
        XCTAssertTrue(foundBlue, "Block quote bar (┃) should use systemBlue color")
    }

    // MARK: - Thematic Break Layout

    func testThematicBreakLayoutRendersHorizontalRule() async throws {
        let layout = await TestHelper.solveLayout("---")
        let hrLayout = layout.children[0]

        guard let attrStr = hrLayout.attributedString else {
            XCTFail("Expected attributed string for thematic break")
            return
        }

        let text = attrStr.string
        XCTAssertEqual(text, String(repeating: "─", count: 40),
                       "Thematic break should render as 40 horizontal box-drawing characters")

        // Verify gray color
        var foundGray = false
        attrStr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            if let color = value as? Color, color == Color.gray { foundGray = true }
        }
        XCTAssertTrue(foundGray, "Thematic break should use gray foreground color")
    }

    // MARK: - Mixed Inline Formatting in Paragraph

    func testBoldInsideParagraphLayoutMixesFonts() async throws {
        let layout = await TestHelper.solveLayout("Normal **bold** normal")
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string")
            return
        }

        var fontRuns = 0
        attrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: attrStr.length)) { _, _, _ in
            fontRuns += 1
        }
        XCTAssertGreaterThanOrEqual(fontRuns, 2,
            "Mixed bold+normal text should produce multiple font runs")
    }

    func testItalicInsideParagraphLayoutMixesFonts() async throws {
        let layout = await TestHelper.solveLayout("Normal *italic* normal")
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string")
            return
        }

        var fontRuns = 0
        attrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: attrStr.length)) { _, _, _ in
            fontRuns += 1
        }
        XCTAssertGreaterThanOrEqual(fontRuns, 2,
            "Mixed italic+normal text should produce multiple font runs")
    }

    func testStrikethroughInsideParagraphMixesAttributes() async throws {
        let layout = await TestHelper.solveLayout("Normal ~~struck~~ normal")
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string")
            return
        }

        // Verify strikethrough only on middle portion
        var strikethroughRanges: [NSRange] = []
        attrStr.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: attrStr.length)) { value, range, _ in
            if let style = value as? Int, style != 0 {
                strikethroughRanges.append(range)
            }
        }
        XCTAssertFalse(strikethroughRanges.isEmpty, "Should have strikethrough on 'struck' portion")
        // The strikethrough should not cover the entire string
        let totalStrikeLength = strikethroughRanges.reduce(0) { $0 + $1.length }
        XCTAssertLessThan(totalStrikeLength, attrStr.length,
            "Strikethrough should not cover the entire string")
    }

    func testBoldAndItalicCombined() async throws {
        let layout = await TestHelper.solveLayout("***both***")
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string")
            return
        }

        var foundBoldItalic = false
        attrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            guard let font = value as? Font else { return }
            #if canImport(UIKit)
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitBold) && traits.contains(.traitItalic) { foundBoldItalic = true }
            #elseif canImport(AppKit)
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) && traits.contains(.italicFontMask) { foundBoldItalic = true }
            #endif
        }
        XCTAssertTrue(foundBoldItalic, "***text*** should produce a font with both bold and italic traits")
    }

    func testBoldWithStrikethrough() async throws {
        let layout = await TestHelper.solveLayout("**~~bold struck~~**")
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string")
            return
        }

        var foundBold = false
        var foundStrikethrough = false

        attrStr.enumerateAttributes(in: NSRange(location: 0, length: attrStr.length)) { attrs, _, _ in
            if let font = attrs[.font] as? Font {
                #if canImport(UIKit)
                if font.fontDescriptor.symbolicTraits.contains(.traitBold) { foundBold = true }
                #elseif canImport(AppKit)
                if NSFontManager.shared.traits(of: font).contains(.boldFontMask) { foundBold = true }
                #endif
            }
            if let style = attrs[.strikethroughStyle] as? Int, style == NSUnderlineStyle.single.rawValue {
                foundStrikethrough = true
            }
        }

        XCTAssertTrue(foundBold, "Should have bold font trait")
        XCTAssertTrue(foundStrikethrough, "Should have strikethrough attribute")
    }

    // MARK: - Inline Code, Link, Image Layout

    func testInlineCodeInsideParagraph() async throws {
        let layout = await TestHelper.solveLayout("Use `code` here")
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string")
            return
        }

        var foundCodeBackground = false
        attrStr.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: attrStr.length)) { value, range, _ in
            if value != nil {
                let substring = (attrStr.string as NSString).substring(with: range)
                if substring.contains("code") { foundCodeBackground = true }
            }
        }
        XCTAssertTrue(foundCodeBackground, "Inline code should have a background color")
    }

    func testLinkInsideParagraph() async throws {
        let layout = await TestHelper.solveLayout("See [link](https://example.com) here")
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string")
            return
        }

        var foundBlue = false
        var foundUnderline = false
        var foundLinkURL = false

        attrStr.enumerateAttributes(in: NSRange(location: 0, length: attrStr.length)) { attrs, _, _ in
            if let color = attrs[.foregroundColor] as? Color, color == Color.systemBlue {
                foundBlue = true
            }
            if let style = attrs[.underlineStyle] as? Int, style == NSUnderlineStyle.single.rawValue {
                foundUnderline = true
            }
            if let url = attrs[.link] as? URL, url.absoluteString == "https://example.com" {
                foundLinkURL = true
            }
        }

        XCTAssertTrue(foundBlue, "Link should use systemBlue foreground color")
        XCTAssertTrue(foundUnderline, "Link should have underline style")
        XCTAssertTrue(foundLinkURL, "Link should have .link URL attribute")
    }

    func testImageAltTextFallback() async throws {
        let layout = await TestHelper.solveLayout("![alt text](https://example.com/img.png)")
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string")
            return
        }

        let text = attrStr.string
        XCTAssertTrue(text.contains("[alt text]"),
            "Image should render alt text in brackets, got: \(text)")

        var foundSecondaryColor = false
        attrStr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            if let color = value as? Color, color == Color.secondaryLabelColor {
                foundSecondaryColor = true
            }
        }
        XCTAssertTrue(foundSecondaryColor, "Image alt text should use secondaryLabelColor")
    }

    func testMathLayoutProducesOutput() async throws {
        // MathRenderer may succeed (image attachment) or fall back to raw equation text
        let markdown = "$E=mc^2$"
        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])
        let solver = LayoutSolver()
        let layout = await solver.solve(node: doc, constrainedToWidth: 400)

        guard let attrStr = layout.children.first?.attributedString else {
            XCTFail("Expected attributed string for math layout")
            return
        }

        // Either the raw equation text appears (fallback) or an attachment character appears (rendered)
        let text = attrStr.string
        let hasEquation = text.contains("E=mc^2")
        let hasAttachment = text.contains("\u{FFFC}") // Object replacement character from NSTextAttachment
        XCTAssertTrue(hasEquation || hasAttachment,
            "Math layout should produce either equation text or image attachment, got: \(text)")
    }
}
