//
//  AppearanceColorResolver.swift
//  MarkdownKit
//
//  Internal helpers that convert platform semantic colors into concrete RGB
//  values for a given explicit `MarkdownAppearance`, without reading ambient
//  state such as `UITraitCollection.current` or `NSAppearance.current`.
//
//  UIKit:  `UIColor.resolvedColor(with:)` is called with an explicit
//          `UITraitCollection(userInterfaceStyle:)` constructed here.
//  AppKit: `NSAppearance.performAsCurrentDrawingAppearance(_:)` is called on
//          the explicit `.aqua` / `.darkAqua` appearance so that
//          `usingColorSpace(.sRGB)` inside the block sees the right context.
//

import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Core resolver

enum AppearanceColorResolver {

    #if canImport(AppKit)
    private static let appKitResolutionLock = NSLock()
    #endif

    /// Returns a concrete (non-dynamic) `Color` for the given explicit appearance.
    /// Dynamic platform semantic colors (e.g. `.label`, `.labelColor`) are resolved
    /// to their RGB values for the requested appearance; already-concrete colors are
    /// returned unchanged.
    static func resolveColor(_ color: Color, for appearance: MarkdownAppearance) -> Color {
        #if canImport(UIKit)
        let style: UIUserInterfaceStyle = appearance == .dark ? .dark : .light
        let traitCollection = UITraitCollection(userInterfaceStyle: style)
        return color.resolvedColor(with: traitCollection)
        #elseif canImport(AppKit)
        appKitResolutionLock.lock()
        defer { appKitResolutionLock.unlock() }

        let appearanceName: NSAppearance.Name = appearance == .dark ? .darkAqua : .aqua
        guard let targetAppearance = NSAppearance(named: appearanceName) else { return color }
        var result = color
        targetAppearance.performAsCurrentDrawingAppearance {
            if let srgb = color.usingColorSpace(.sRGB) {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
                result = NSColor(srgbRed: r, green: g, blue: b, alpha: a)
            }
            // If conversion to sRGB fails the original color is kept, which is
            // acceptable for non-RGB color spaces that are already concrete.
        }
        return result
        #endif
    }

    /// Walks `attrStr` and replaces every recognized color attribute with its
    /// concrete resolved value. Handles `.foregroundColor`, `.backgroundColor`,
    /// `.strokeColor`, `.underlineColor`, and `.strikethroughColor`. All other
    /// attributes and the string geometry are preserved unchanged.
    static func resolveColors(
        in attrStr: NSAttributedString,
        for appearance: MarkdownAppearance
    ) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: attrStr.length)
        guard fullRange.length > 0 else { return attrStr }
        let colorKeys: [NSAttributedString.Key] = [
            .foregroundColor,
            .backgroundColor,
            .strokeColor,
            .underlineColor,
            .strikethroughColor
        ]

        var changes: [(NSAttributedString.Key, NSRange, Color)] = []
        attrStr.enumerateAttributes(in: fullRange) { attributes, range, _ in
            for key in colorKeys {
                guard let color = attributes[key] as? Color else { continue }
                changes.append((key, range, resolveColor(color, for: appearance)))
            }
        }

        guard !changes.isEmpty else { return attrStr }
        let result = NSMutableAttributedString(attributedString: attrStr)
        for (key, range, color) in changes {
            result.addAttribute(key, value: color, range: range)
        }
        return result
    }
}

// MARK: - ColorToken convenience

extension ColorToken {
    /// Returns a copy of this token with both foreground and background resolved
    /// to concrete RGB values for the given explicit appearance.
    func resolved(for appearance: MarkdownAppearance) -> ColorToken {
        ColorToken(
            foreground: AppearanceColorResolver.resolveColor(foreground, for: appearance),
            background: AppearanceColorResolver.resolveColor(background, for: appearance)
        )
    }
}

// MARK: - SyntaxColors convenience

extension Theme.SyntaxColors {
    /// Returns a copy with every syntax color resolved to a concrete RGB value
    /// for the given explicit appearance.
    func resolved(for appearance: MarkdownAppearance) -> Theme.SyntaxColors {
        Theme.SyntaxColors(
            keyword:       AppearanceColorResolver.resolveColor(keyword,       for: appearance),
            string:        AppearanceColorResolver.resolveColor(string,        for: appearance),
            type:          AppearanceColorResolver.resolveColor(type,          for: appearance),
            call:          AppearanceColorResolver.resolveColor(call,          for: appearance),
            number:        AppearanceColorResolver.resolveColor(number,        for: appearance),
            comment:       AppearanceColorResolver.resolveColor(comment,       for: appearance),
            property:      AppearanceColorResolver.resolveColor(property,      for: appearance),
            dotAccess:     AppearanceColorResolver.resolveColor(dotAccess,     for: appearance),
            preprocessing: AppearanceColorResolver.resolveColor(preprocessing, for: appearance)
        )
    }
}
