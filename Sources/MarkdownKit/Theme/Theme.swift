//
//  Theme.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A centralized configuration defining typography, colors, and layout metrics
/// that dictate exactly how the raw Markdown AST gets styled and measured.
public struct Theme: Equatable {
    public let typography: Typography
    public let colors: Colors
    public let codeBlock: CodeBlockStyle
    public let blockQuote: BlockQuoteStyle
    public let list: ListStyle
    public let details: DetailsStyle
    public let table: TableStyle
    public let syntaxColors: SyntaxColors
    public let highlight: HighlightStyle
    public let thematicBreak: ThematicBreakStyle

    public struct Typography: Equatable {
        public let header1: TypographyToken
        public let header2: TypographyToken
        public let header3: TypographyToken
        public let paragraph: TypographyToken
        public let codeBlock: TypographyToken

        public init(
            header1: TypographyToken,
            header2: TypographyToken,
            header3: TypographyToken,
            paragraph: TypographyToken,
            codeBlock: TypographyToken
        ) {
            self.header1 = header1
            self.header2 = header2
            self.header3 = header3
            self.paragraph = paragraph
            self.codeBlock = codeBlock
        }
    }

    public struct Colors: Equatable {
        public let textColor: ColorToken
        public let codeColor: ColorToken
        public let inlineCodeColor: ColorToken
        public let tableColor: ColorToken
        public let linkColor: ColorToken
        public let blockQuoteColor: ColorToken
        public let thematicBreakColor: ColorToken

        public init(
            textColor: ColorToken,
            codeColor: ColorToken,
            inlineCodeColor: ColorToken? = nil,
            tableColor: ColorToken,
            linkColor: ColorToken? = nil,
            blockQuoteColor: ColorToken? = nil,
            thematicBreakColor: ColorToken? = nil
        ) {
            self.textColor = textColor
            self.codeColor = codeColor
            self.inlineCodeColor = inlineCodeColor ?? codeColor
            self.tableColor = tableColor
            self.linkColor = linkColor ?? ColorToken(foreground: .systemBlue)
            self.blockQuoteColor = blockQuoteColor ?? ColorToken(foreground: .systemBlue, background: .gray)
            self.thematicBreakColor = thematicBreakColor ?? ColorToken(foreground: .gray)
        }
    }

    // MARK: - Code Block Style

    public struct CodeBlockStyle: Equatable {
        public let cornerRadius: CGFloat
        public let layoutTotalInset: CGFloat
        public let viewPadding: CGFloat
        public let labelFont: Font
        public let labelParagraphSpacing: CGFloat
        public let inlineCodeFontSizeRatio: CGFloat
        public let inlineCodeMinFontSize: CGFloat
        public let copyButtonSize: CGFloat
        public let copyButtonCornerRadius: CGFloat
        public let copyButtonMargin: CGFloat
        public let copyButtonIconSize: CGFloat
        public let macOSCornerRadius: CGFloat
        public let macOSTextContainerInset: CGSize

        public init(
            cornerRadius: CGFloat = 8,
            layoutTotalInset: CGFloat = 16,
            viewPadding: CGFloat = 16,
            labelFont: Font = Font.monospacedSystemFont(ofSize: 11, weight: .semibold),
            labelParagraphSpacing: CGFloat = 6,
            inlineCodeFontSizeRatio: CGFloat = 0.92,
            inlineCodeMinFontSize: CGFloat = 11,
            copyButtonSize: CGFloat = 30,
            copyButtonCornerRadius: CGFloat = 6,
            copyButtonMargin: CGFloat = 8,
            copyButtonIconSize: CGFloat = 14,
            macOSCornerRadius: CGFloat = 6,
            macOSTextContainerInset: CGSize = CGSize(width: 8, height: 8)
        ) {
            self.cornerRadius = cornerRadius
            self.layoutTotalInset = layoutTotalInset
            self.viewPadding = viewPadding
            self.labelFont = labelFont
            self.labelParagraphSpacing = labelParagraphSpacing
            self.inlineCodeFontSizeRatio = inlineCodeFontSizeRatio
            self.inlineCodeMinFontSize = inlineCodeMinFontSize
            self.copyButtonSize = copyButtonSize
            self.copyButtonCornerRadius = copyButtonCornerRadius
            self.copyButtonMargin = copyButtonMargin
            self.copyButtonIconSize = copyButtonIconSize
            self.macOSCornerRadius = macOSCornerRadius
            self.macOSTextContainerInset = macOSTextContainerInset
        }
    }

    // MARK: - Block Quote Style

    public struct BlockQuoteStyle: Equatable {
        public let indent: CGFloat
        public let barCharacter: String

        public init(
            indent: CGFloat = 16,
            barCharacter: String = "┃ "
        ) {
            self.indent = indent
            self.barCharacter = barCharacter
        }
    }

    // MARK: - List Style

    public struct ListStyle: Equatable {
        public let bulletCharacter: String
        public let checkedCharacter: String
        public let uncheckedCharacter: String
        public let nestedIndentDelta: CGFloat

        public init(
            bulletCharacter: String = "• ",
            checkedCharacter: String = "☑ ",
            uncheckedCharacter: String = "☐ ",
            nestedIndentDelta: CGFloat = 16
        ) {
            self.bulletCharacter = bulletCharacter
            self.checkedCharacter = checkedCharacter
            self.uncheckedCharacter = uncheckedCharacter
            self.nestedIndentDelta = nestedIndentDelta
        }
    }

    // MARK: - Details Style

    public struct DetailsStyle: Equatable {
        public let openDisclosure: String
        public let closedDisclosure: String

        public init(
            openDisclosure: String = "▼ ",
            closedDisclosure: String = "▶ "
        ) {
            self.openDisclosure = openDisclosure
            self.closedDisclosure = closedDisclosure
        }
    }

    // MARK: - Table Style

    public struct TableStyle: Equatable {
        public let cornerRadius: CGFloat
        public let borderWidth: CGFloat
        public let cellPaddingH: CGFloat
        public let cellPaddingV: CGFloat
        public let dividerHeight: CGFloat
        public let fontSize: CGFloat
        public let uiKitHorizontalInset: CGFloat
        public let appKitHorizontalPadding: CGFloat
        public let appKitBorderAllowance: CGFloat
        public let minimumReadableColumnWidth: CGFloat
        public let cellParagraphSpacing: CGFloat
        public let narrowFallbackMaxChars: Int
        public let alternatingRowAlpha: CGFloat
        public let separatorAlpha: CGFloat

        public init(
            cornerRadius: CGFloat = 8,
            borderWidth: CGFloat = 1,
            cellPaddingH: CGFloat = 12,
            cellPaddingV: CGFloat = 8,
            dividerHeight: CGFloat = 0.5,
            fontSize: CGFloat = 13,
            uiKitHorizontalInset: CGFloat = 8,
            appKitHorizontalPadding: CGFloat = 16,
            appKitBorderAllowance: CGFloat = 2,
            minimumReadableColumnWidth: CGFloat = 36,
            cellParagraphSpacing: CGFloat = 2,
            narrowFallbackMaxChars: Int = 12,
            alternatingRowAlpha: CGFloat = 0.45,
            separatorAlpha: CGFloat = 0.55
        ) {
            self.cornerRadius = cornerRadius
            self.borderWidth = borderWidth
            self.cellPaddingH = cellPaddingH
            self.cellPaddingV = cellPaddingV
            self.dividerHeight = dividerHeight
            self.fontSize = fontSize
            self.uiKitHorizontalInset = uiKitHorizontalInset
            self.appKitHorizontalPadding = appKitHorizontalPadding
            self.appKitBorderAllowance = appKitBorderAllowance
            self.minimumReadableColumnWidth = minimumReadableColumnWidth
            self.cellParagraphSpacing = cellParagraphSpacing
            self.narrowFallbackMaxChars = narrowFallbackMaxChars
            self.alternatingRowAlpha = alternatingRowAlpha
            self.separatorAlpha = separatorAlpha
        }
    }

    // MARK: - Syntax Colors

    public struct SyntaxColors: Equatable {
        public let keyword: Color
        public let string: Color
        public let type: Color
        public let call: Color
        public let number: Color
        public let comment: Color
        public let property: Color
        public let dotAccess: Color
        public let preprocessing: Color

        public init(
            keyword: Color = Color(red: 0.8, green: 0.1, blue: 0.5, alpha: 1.0),
            string: Color = Color(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0),
            type: Color = Color(red: 0.1, green: 0.6, blue: 0.7, alpha: 1.0),
            call: Color = Color(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0),
            number: Color = Color(red: 0.6, green: 0.4, blue: 0.9, alpha: 1.0),
            comment: Color = Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
            property: Color = Color(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0),
            dotAccess: Color = Color(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0),
            preprocessing: Color = Color(red: 0.6, green: 0.4, blue: 0.1, alpha: 1.0)
        ) {
            self.keyword = keyword
            self.string = string
            self.type = type
            self.call = call
            self.number = number
            self.comment = comment
            self.property = property
            self.dotAccess = dotAccess
            self.preprocessing = preprocessing
        }
    }

    // MARK: - Highlight Style

    public struct HighlightStyle: Equatable {
        public let cornerRadius: CGFloat
        public let darkModeAlpha: CGFloat
        public let lightModeAlpha: CGFloat
        public let insetDX: CGFloat
        public let insetDY: CGFloat
        public let fadeInDuration: CGFloat
        public let fadeOutDuration: CGFloat

        public init(
            cornerRadius: CGFloat = 3,
            darkModeAlpha: CGFloat = 0.22,
            lightModeAlpha: CGFloat = 0.11,
            insetDX: CGFloat = -2,
            insetDY: CGFloat = -1,
            fadeInDuration: CGFloat = 0.1,
            fadeOutDuration: CGFloat = 0.15
        ) {
            self.cornerRadius = cornerRadius
            self.darkModeAlpha = darkModeAlpha
            self.lightModeAlpha = lightModeAlpha
            self.insetDX = insetDX
            self.insetDY = insetDY
            self.fadeInDuration = fadeInDuration
            self.fadeOutDuration = fadeOutDuration
        }
    }

    // MARK: - Thematic Break Style

    public struct ThematicBreakStyle: Equatable {
        public let paddingTop: CGFloat
        public let paddingBottom: CGFloat
        public let dividerHeight: CGFloat

        public init(
            paddingTop: CGFloat = 16,
            paddingBottom: CGFloat = 24,
            dividerHeight: CGFloat = 0.5
        ) {
            self.paddingTop = paddingTop
            self.paddingBottom = paddingBottom
            self.dividerHeight = dividerHeight
        }
    }

    // MARK: - Init

    public init(
        typography: Typography,
        colors: Colors,
        codeBlock: CodeBlockStyle = CodeBlockStyle(),
        blockQuote: BlockQuoteStyle = BlockQuoteStyle(),
        list: ListStyle = ListStyle(),
        details: DetailsStyle = DetailsStyle(),
        table: TableStyle = TableStyle(),
        syntaxColors: SyntaxColors = SyntaxColors(),
        highlight: HighlightStyle = HighlightStyle(),
        thematicBreak: ThematicBreakStyle = ThematicBreakStyle()
    ) {
        self.typography = typography
        self.colors = colors
        self.codeBlock = codeBlock
        self.blockQuote = blockQuote
        self.list = list
        self.details = details
        self.table = table
        self.syntaxColors = syntaxColors
        self.highlight = highlight
        self.thematicBreak = thematicBreak
    }
    
    /// The default cross-platform theme for MarkdownKit.
    public static var `default`: Theme {
        let h1 = TypographyToken(font: Font.boldSystemFont(ofSize: 32))
        let h2 = TypographyToken(font: Font.boldSystemFont(ofSize: 24))
        let h3 = TypographyToken(font: Font.boldSystemFont(ofSize: 20))
        let p = TypographyToken(font: Font.systemFont(ofSize: 16))
        let code = TypographyToken(font: Font.monospacedSystemFont(ofSize: 14, weight: .regular))
        
        let typography = Typography(
            header1: h1,
            header2: h2,
            header3: h3,
            paragraph: p,
            codeBlock: code
        )
        
#if canImport(UIKit)
        let textC = ColorToken(foreground: .label)
        let codeC = ColorToken(foreground: .label, background: .secondarySystemFill)
        let inlineCodeC = ColorToken(foreground: .label, background: .tertiarySystemFill)
        let tableC = ColorToken(foreground: .separator, background: .secondarySystemGroupedBackground)
#elseif canImport(AppKit)
        let textC = ColorToken(foreground: .labelColor)
        let codeC = ColorToken(
            foreground: .labelColor,
            background: NSColor.controlAccentColor.withAlphaComponent(0.14)
        )
        let inlineCodeC = ColorToken(
            foreground: .labelColor,
            background: NSColor.controlAccentColor.withAlphaComponent(0.22)
        )
        let tableC = ColorToken(
            foreground: NSColor.labelColor.withAlphaComponent(0.15),
            background: NSColor.labelColor.withAlphaComponent(0.04)
        )
#endif
        
        return Theme(
            typography: typography,
            colors: Colors(
                textColor: textC,
                codeColor: codeC,
                inlineCodeColor: inlineCodeC,
                tableColor: tableC
            )
        )
    }
}
