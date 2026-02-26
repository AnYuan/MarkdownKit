//
//  SplashHighlighter.swift
//  MyMarkdown
//

import Foundation
import Splash

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A thread-safe utility wrapper around the `Splash` syntax highlighter.
/// This executes efficiently on background queues to generate fully styled `NSAttributedString`s
/// before the LayoutSolver measures them.
public struct SplashHighlighter {
    
    private let highlighter: SyntaxHighlighter<AttributedStringOutputFormat>
    private let theme: Theme
    
    public init(theme: Theme = .default) {
        self.theme = theme
        
        // Map our global Theme's typography to Splash's specific Font format
        let splashFont = splashFontFrom(token: theme.codeBlock)
        
        // Define a custom Splash theme bridging our ColorTokens for Light/Dark mode parity
        let splashTheme = Splash.Theme(
            font: splashFont,
            plainTextColor: splashColor(from: theme.textColor.foreground),
            tokenColors: [
                .keyword: splashColor(from: Color(red: 0.8, green: 0.1, blue: 0.5, alpha: 1.0)), // Pink/Purple
                .string: splashColor(from: Color(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0)), // Red
                .type: splashColor(from: Color(red: 0.1, green: 0.6, blue: 0.7, alpha: 1.0)), // Cyan/Teal
                .call: splashColor(from: Color(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0)), // Blue
                .number: splashColor(from: Color(red: 0.6, green: 0.4, blue: 0.9, alpha: 1.0)), // Purple
                .comment: splashColor(from: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)), // Gray
                .property: splashColor(from: Color(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0)), // Blue
                .dotAccess: splashColor(from: Color(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0)), // Blue
                .preprocessing: splashColor(from: Color(red: 0.6, green: 0.4, blue: 0.1, alpha: 1.0)) // Brown/Orange
            ]
        )
        
        let format = AttributedStringOutputFormat(theme: splashTheme)
        self.highlighter = SyntaxHighlighter(format: format)
    }
    
    /// Returns a syntax-highlighted attributed string for the given code.
    /// - Parameters:
    ///   - code: The raw string of code.
    ///   - language: Optional language identifier (e.g. "swift"). Splash defaults to Swift if unknown, which is usually fine for general C-family syntax.
    public func highlight(_ code: String, language: String? = nil) -> NSAttributedString {
        return highlighter.highlight(code)
    }
}

// MARK: - Platform Helpers
private func splashFontFrom(token: TypographyToken) -> Splash.Font {
#if canImport(UIKit)
    return Splash.Font(size: token.font.pointSize)
#elseif canImport(AppKit)
    return Splash.Font(size: token.font.pointSize)
#endif
}

private func splashColor(from color: Color) -> Splash.Color {
#if canImport(UIKit)
    return color
#elseif canImport(AppKit)
    return color
#endif
}
