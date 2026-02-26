//
//  Theme.swift
//  MyMarkdown
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
    
    public init(
        header1: TypographyToken,
        header2: TypographyToken,
        header3: TypographyToken,
        paragraph: TypographyToken,
        codeBlock: TypographyToken,
        textColor: ColorToken,
        codeColor: ColorToken
    ) {
        self.header1 = header1
        self.header2 = header2
        self.header3 = header3
        self.paragraph = paragraph
        self.codeBlock = codeBlock
        self.textColor = textColor
        self.codeColor = codeColor
    }
    
    /// The default cross-platform theme for MyMarkdown.
    public static var `default`: Theme {
        let h1 = TypographyToken(font: Font.boldSystemFont(ofSize: 32))
        let h2 = TypographyToken(font: Font.boldSystemFont(ofSize: 24))
        let h3 = TypographyToken(font: Font.boldSystemFont(ofSize: 20))
        let p = TypographyToken(font: Font.systemFont(ofSize: 16))
        let code = TypographyToken(font: Font.monospacedSystemFont(ofSize: 14, weight: .regular))
        
#if canImport(UIKit)
        let textC = ColorToken(foreground: .label)
        let codeC = ColorToken(foreground: .label, background: .secondarySystemBackground)
#elseif canImport(AppKit)
        let textC = ColorToken(foreground: .labelColor)
        let codeC = ColorToken(foreground: .labelColor, background: .windowBackgroundColor)
#endif
        
        return Theme(
            header1: h1,
            header2: h2,
            header3: h3,
            paragraph: p,
            codeBlock: code,
            textColor: textC,
            codeColor: codeC
        )
    }
}
