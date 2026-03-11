//
//  TextKitCalculator.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

import os

/// A strictly background-queue-only utility class that calculates the bounding sizes
/// of `NSAttributedString` blocks before they are ever mounted to the main thread UI.
///
/// On AppKit we intentionally mirror the `NSTextView` renderer with TextKit 1 so
/// complex attributed content such as `NSTextTable` measures the same way it draws.
public final class TextKitCalculator {
    
    // CoreText's internal glyph fallback dictionaries randomly fail under high concurrency
    // so we serialize the actual layout fragment pipeline to maintain safety.
    private static nonisolated(unsafe) var layoutLock = os_unfair_lock_s()
    
    public init() {}
    
    /// Calculates the exact bounding size for a given attributed string constrained to a width.
    ///
    /// - Important: Must only be called on a background thread.
    ///
    /// - Parameters:
    ///   - attributedString: The dynamically typed and themed string to measure.
    ///   - maxWidth: The maximum width of the containing viewport (e.g., the device screen width).
    /// - Returns: The precise `CGSize` necessary to display the text without clipping.
    public func calculateSize(for attributedString: NSAttributedString, constrainedToWidth maxWidth: CGFloat) -> CGSize {
        guard attributedString.length > 0 else { return .zero }

        // Force layout resolution inside a safety lock to avoid CoreText NSFont proxy crashes.
        os_unfair_lock_lock(&Self.layoutLock)
        defer { os_unfair_lock_unlock(&Self.layoutLock) }

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        return calculateSizeAppKit(for: attributedString, constrainedToWidth: maxWidth)
        #else
        return calculateSizeTextKit2(for: attributedString, constrainedToWidth: maxWidth)
        #endif
    }
}

private extension TextKitCalculator {
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    func calculateSizeAppKit(
        for attributedString: NSAttributedString,
        constrainedToWidth maxWidth: CGFloat
    ) -> CGSize {
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        )

        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let rect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }
    #endif

    #if canImport(UIKit)
    func calculateSizeTextKit2(
        for attributedString: NSAttributedString,
        constrainedToWidth maxWidth: CGFloat
    ) -> CGSize {
        let textStorage = NSTextStorage()
        let textContainer = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let layoutManager = NSTextLayoutManager()
        let textContentStorage = NSTextContentStorage()

        textContentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = textContainer
        textContentStorage.textStorage = textStorage
        textContainer.lineFragmentPadding = 0

        textStorage.setAttributedString(attributedString)
        layoutManager.ensureLayout(for: layoutManager.documentRange)

        guard let _ = layoutManager.textLayoutFragment(for: layoutManager.documentRange.location) else {
            return .zero
        }

        let rect = layoutManager.usageBoundsForTextContainer
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }
    #endif
}
