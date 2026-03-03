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
public struct Theme {
    public let header1: TypographyToken
    public let header2: TypographyToken
    public let header3: TypographyToken
    public let paragraph: TypographyToken
    public let codeBlock: TypographyToken
    
    public let textColor: ColorToken
    public let codeColor: ColorToken
    public let inlineCodeColor: ColorToken
    public let tableColor: ColorToken
    
    public init(
        header1: TypographyToken,
        header2: TypographyToken,
        header3: TypographyToken,
        paragraph: TypographyToken,
        codeBlock: TypographyToken,
        textColor: ColorToken,
        codeColor: ColorToken,
        inlineCodeColor: ColorToken? = nil,
        tableColor: ColorToken
    ) {
        self.header1 = header1
        self.header2 = header2
        self.header3 = header3
        self.paragraph = paragraph
        self.codeBlock = codeBlock
        self.textColor = textColor
        self.codeColor = codeColor
        self.inlineCodeColor = inlineCodeColor ?? codeColor
        self.tableColor = tableColor
    }
    
    /// The default cross-platform theme for MarkdownKit.
    public static var `default`: Theme {
        let h1 = TypographyToken(font: Font.boldSystemFont(ofSize: 32))
        let h2 = TypographyToken(font: Font.boldSystemFont(ofSize: 24))
        let h3 = TypographyToken(font: Font.boldSystemFont(ofSize: 20))
        let p = TypographyToken(font: Font.systemFont(ofSize: 16))
        let code = TypographyToken(font: Font.monospacedSystemFont(ofSize: 14, weight: .regular))
        
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
            header1: h1,
            header2: h2,
            header3: h3,
            paragraph: p,
            codeBlock: code,
            textColor: textC,
            codeColor: codeC,
            inlineCodeColor: inlineCodeC,
            tableColor: tableC
        )
    }
}
