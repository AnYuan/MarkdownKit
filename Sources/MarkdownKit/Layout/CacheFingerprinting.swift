//
//  CacheFingerprinting.swift
//  MarkdownKit
//
//  Hash helpers shared by `LayoutSolver` so theme / token / adapter / policy
//  changes are reflected in the `LayoutCache` variant hash.
//
//  Theme intentionally stays `Equatable` and does not adopt `Hashable`. Color
//  and Font on Apple platforms have surprising `Hashable` semantics
//  (UIColor instances created from different APIs are equal but hash to
//  different values), so this file builds a content-only fingerprint using
//  `Hasher.combine` directly.
//

import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Theme

extension Theme {
    /// Mixes every theme-derived value the layout cache must invalidate on
    /// into the supplied hasher. Used by `LayoutSolver` when constructing the
    /// `cacheVariantHash` it threads through every `LayoutCache` key.
    public func cacheFingerprint(into hasher: inout Hasher) {
        typography.header1.cacheFingerprint(into: &hasher)
        typography.header2.cacheFingerprint(into: &hasher)
        typography.header3.cacheFingerprint(into: &hasher)
        typography.paragraph.cacheFingerprint(into: &hasher)
        typography.codeBlock.cacheFingerprint(into: &hasher)

        colors.textColor.cacheFingerprint(into: &hasher)
        colors.codeColor.cacheFingerprint(into: &hasher)
        colors.inlineCodeColor.cacheFingerprint(into: &hasher)
        colors.tableColor.cacheFingerprint(into: &hasher)
        colors.linkColor.cacheFingerprint(into: &hasher)
        colors.blockQuoteColor.cacheFingerprint(into: &hasher)
        colors.thematicBreakColor.cacheFingerprint(into: &hasher)

        codeBlock.cacheFingerprint(into: &hasher)

        hasher.combine(Double(blockQuote.indent))
        hasher.combine(blockQuote.barCharacter)

        hasher.combine(list.bulletCharacter)
        hasher.combine(list.checkedCharacter)
        hasher.combine(list.uncheckedCharacter)
        hasher.combine(Double(list.nestedIndentDelta))

        hasher.combine(details.openDisclosure)
        hasher.combine(details.closedDisclosure)

        table.cacheFingerprint(into: &hasher)
        syntaxColors.cacheFingerprint(into: &hasher)

        hasher.combine(Double(highlight.cornerRadius))
        hasher.combine(Double(highlight.darkModeAlpha))
        hasher.combine(Double(highlight.lightModeAlpha))
        hasher.combine(Double(highlight.insetDX))
        hasher.combine(Double(highlight.insetDY))
        hasher.combine(Double(highlight.fadeInDuration))
        hasher.combine(Double(highlight.fadeOutDuration))

        hasher.combine(Double(thematicBreak.paddingTop))
        hasher.combine(Double(thematicBreak.paddingBottom))
        hasher.combine(Double(thematicBreak.dividerHeight))
    }
}

extension TypographyToken {
    public func cacheFingerprint(into hasher: inout Hasher) {
        font.cacheFingerprint(into: &hasher)
        hasher.combine(Double(lineHeightMultiple))
        hasher.combine(Double(paragraphSpacing))
    }
}

extension ColorToken {
    public func cacheFingerprint(into hasher: inout Hasher) {
        foreground.cacheFingerprint(into: &hasher)
        background.cacheFingerprint(into: &hasher)
    }
}

extension Theme.CodeBlockStyle {
    public func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(Double(cornerRadius))
        hasher.combine(Double(layoutTotalInset))
        hasher.combine(Double(viewPadding))
        labelFont.cacheFingerprint(into: &hasher)
        hasher.combine(Double(labelParagraphSpacing))
        hasher.combine(Double(inlineCodeFontSizeRatio))
        hasher.combine(Double(inlineCodeMinFontSize))
        hasher.combine(Double(copyButtonSize))
        hasher.combine(Double(copyButtonCornerRadius))
        hasher.combine(Double(copyButtonMargin))
        hasher.combine(Double(copyButtonIconSize))
        hasher.combine(Double(macOSCornerRadius))
        hasher.combine(Double(macOSTextContainerInset.width))
        hasher.combine(Double(macOSTextContainerInset.height))
    }
}

extension Theme.TableStyle {
    public func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(Double(cornerRadius))
        hasher.combine(Double(borderWidth))
        hasher.combine(Double(cellPaddingH))
        hasher.combine(Double(cellPaddingV))
        hasher.combine(Double(dividerHeight))
        hasher.combine(Double(fontSize))
        hasher.combine(Double(uiKitHorizontalInset))
        hasher.combine(Double(appKitHorizontalPadding))
        hasher.combine(Double(appKitBorderAllowance))
        hasher.combine(Double(minimumReadableColumnWidth))
        hasher.combine(Double(cellParagraphSpacing))
        hasher.combine(narrowFallbackMaxChars)
        hasher.combine(Double(alternatingRowAlpha))
        hasher.combine(Double(separatorAlpha))
    }
}

extension Theme.SyntaxColors {
    public func cacheFingerprint(into hasher: inout Hasher) {
        keyword.cacheFingerprint(into: &hasher)
        string.cacheFingerprint(into: &hasher)
        type.cacheFingerprint(into: &hasher)
        call.cacheFingerprint(into: &hasher)
        number.cacheFingerprint(into: &hasher)
        comment.cacheFingerprint(into: &hasher)
        property.cacheFingerprint(into: &hasher)
        dotAccess.cacheFingerprint(into: &hasher)
        preprocessing.cacheFingerprint(into: &hasher)
    }
}

// MARK: - Platform color / font

extension Font {
    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(fontName)
        hasher.combine(Double(pointSize))
        hasher.combine(fontDescriptor.symbolicTraits.rawValue)
    }
}

extension Color {
    /// Best-effort content-based hash. Falls back to `String(describing:)` for
    /// non-RGB color spaces; those are rare in practice and still produce a
    /// stable identifier for cache invalidation.
    func cacheFingerprint(into hasher: inout Hasher) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        #if canImport(UIKit)
        if getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            hasher.combine(Double(red))
            hasher.combine(Double(green))
            hasher.combine(Double(blue))
            hasher.combine(Double(alpha))
            return
        }
        hasher.combine(String(describing: self))
        #elseif canImport(AppKit)
        if let rgb = usingColorSpace(.sRGB) {
            rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            hasher.combine(Double(red))
            hasher.combine(Double(green))
            hasher.combine(Double(blue))
            hasher.combine(Double(alpha))
            return
        }
        hasher.combine(String(describing: self))
        #endif
    }
}

// MARK: - MathRenderingAdapter / DiagramAdapterRegistry / ImageLoadingPolicy

extension MathRenderingAdapter {
    /// Default implementation hashes the conformer's type name. Custom adapters
    /// with their own internal configuration can override this method.
    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: type(of: self)))
    }
}

extension DiagramAdapterRegistry {
    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(cacheFingerprint)
    }
}

extension ImageLoadingPolicy {
    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(cacheFingerprint)
    }
}
