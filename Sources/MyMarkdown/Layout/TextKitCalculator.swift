//
//  TextKitCalculator.swift
//  MyMarkdown
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A strictly background-queue-only utility class that uses Apple's native TextKit 2
/// (via `NSTextLayoutManager`) to precisely calculate the bounding sizes of
/// `NSAttributedString` blocks before they are ever mounted to the main thread UI.
public final class TextKitCalculator {
    
    // Core TextKit 2 components
    private let textStorage = NSTextStorage()
    private let textContainer = NSTextContainer(size: .zero)
    private let layoutManager = NSTextLayoutManager()
    private let textContentStorage = NSTextContentStorage()
    
    public init() {
        // Wire up the TextKit 2 stack
        textContentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = textContainer
        textContentStorage.textStorage = textStorage
        
        // Disable line fragment padding to get absolute exact typography bounds
        textContainer.lineFragmentPadding = 0
    }
    
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
        
        // 1. Update the constraint dimensions
        textContainer.size = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        
        // 2. Inject the text into the TextKit 2 engine
        textStorage.setAttributedString(attributedString)
        
        // 3. Force layout resolution
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        
        // 4. Extract the exact computed frame
        guard let _ = layoutManager.textLayoutFragment(for: layoutManager.documentRange.location) else {
            return .zero
        }
        
        // Depending on whether it's a single fragment or multiple (wrapping),
        // we take the entire bounding rect of the layout manager.
        let rect = layoutManager.usageBoundsForTextContainer
        
        // We ensure we ceil the values so we never clip half-pixels on Retina screens
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }
}
