//
//  TextKitHitTester.swift
//  MarkdownKit
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// Resolves screen coordinates to character indices within a pre-laid-out
/// NSAttributedString, enabling tap-based interaction on rasterized text.
///
/// Uses TextKit 1 (NSLayoutManager) because its `glyphIndex(for:in:)`
/// API provides reliable character-level hit-testing. This mirrors the
/// approach used by Texture (ASTextNode2) and the macOS `InteractiveTextView`.
///
/// Created lazily on first tap — no memory cost for cells that are never tapped.
struct TextKitHitTester {

    private let textStorage: NSTextStorage
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer

    init(attributedString: NSAttributedString, containerSize: CGSize) {
        self.textStorage = NSTextStorage(attributedString: attributedString)
        self.layoutManager = NSLayoutManager()
        self.textContainer = NSTextContainer(size: containerSize)

        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        // Force layout so all glyph positions are computed
        layoutManager.ensureLayout(for: textContainer)
    }

    /// Returns the character index at the given point, or nil if outside text bounds.
    ///
    /// Borrows from Texture's 44x44 expanded touch target: checks 9 points in a
    /// grid around the tap to improve hit rate on small link text.
    func characterIndex(at point: CGPoint) -> Int? {
        // Check center first (fast path)
        if let index = rawCharacterIndex(at: point) {
            return index
        }

        // Expanded 44x44 search: check 8 surrounding points (Texture ASTextNode2 pattern)
        let offsets: [CGPoint] = [
            CGPoint(x: 0, y: -22), CGPoint(x: 0, y: 22),   // top, bottom
            CGPoint(x: -22, y: 0), CGPoint(x: 22, y: 0),   // left, right
            CGPoint(x: -22, y: -22), CGPoint(x: 22, y: -22), // corners
            CGPoint(x: -22, y: 22), CGPoint(x: 22, y: 22),
        ]

        for offset in offsets {
            let expanded = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
            if let index = rawCharacterIndex(at: expanded) {
                return index
            }
        }

        return nil
    }

    /// Looks up a typed attribute at a specific character index.
    func attribute<T>(_ key: NSAttributedString.Key, at index: Int) -> T? {
        guard index >= 0, index < textStorage.length else { return nil }
        return textStorage.attribute(key, at: index, effectiveRange: nil) as? T
    }

    /// Returns the full effective range of the attribute at the given character index.
    func effectiveRange(of key: NSAttributedString.Key, at index: Int) -> NSRange? {
        guard index >= 0, index < textStorage.length else { return nil }
        var range = NSRange()
        guard textStorage.attribute(key, at: index, effectiveRange: &range) != nil else {
            return nil
        }
        return range
    }

    /// Returns the bounding rect for the given character range (for highlight overlay).
    func boundingRect(for range: NSRange) -> CGRect {
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: range,
            actualCharacterRange: nil
        )
        return layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: textContainer
        )
    }

    // MARK: - Private

    private func rawCharacterIndex(at point: CGPoint) -> Int? {
        let usedRect = layoutManager.usedRect(for: textContainer)
        guard usedRect.contains(point) else { return nil }

        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        guard charIndex < textStorage.length else { return nil }
        return charIndex
    }
}
#endif
