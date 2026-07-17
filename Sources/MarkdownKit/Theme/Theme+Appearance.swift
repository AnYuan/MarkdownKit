//
//  Theme+Appearance.swift
//  MarkdownKit
//

extension Theme {
    /// Returns a copy of this theme with every appearance-sensitive color token
    /// resolved to a concrete RGB value for the given explicit `appearance`.
    ///
    /// Non-color fields (typography, metrics, style constants) are preserved
    /// exactly. The resulting theme is safe for off-main layout and drawing
    /// because it no longer contains any dynamic platform colors.
    func resolved(for appearance: MarkdownAppearance) -> Theme {
        Theme(
            typography: typography,
            colors: Colors(
                textColor:         colors.textColor.resolved(for: appearance),
                codeColor:         colors.codeColor.resolved(for: appearance),
                inlineCodeColor:   colors.inlineCodeColor.resolved(for: appearance),
                tableColor:        colors.tableColor.resolved(for: appearance),
                linkColor:         colors.linkColor.resolved(for: appearance),
                blockQuoteColor:   colors.blockQuoteColor.resolved(for: appearance),
                thematicBreakColor: colors.thematicBreakColor.resolved(for: appearance)
            ),
            codeBlock:    codeBlock,
            blockQuote:   blockQuote,
            list:         list,
            details:      details,
            table:        table,
            syntaxColors: syntaxColors.resolved(for: appearance),
            highlight:    highlight,
            thematicBreak: thematicBreak
        )
    }
}
