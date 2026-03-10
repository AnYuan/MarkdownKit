//
//  MarkdownCollectionViewCell.swift
//  MarkdownKit
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// A highly reusable, recycled view cell managed by `UICollectionView`.
/// Its sole responsibility is mounting the pre-calculated `LayoutResult`
/// and displaying the dynamically generated background `CGImage` or `CGContext` snapshots.
public class MarkdownCollectionViewCell: UICollectionViewCell {

    public static let reuseIdentifier = "MarkdownCollectionViewCell"

    /// The specific view container responsible for rendering the assigned AST element.
    private var hostedView: UIView?

    // MARK: - Interaction Callbacks (set by collection view before configure)

    public var onLinkTap: ((URL) -> Void)?
    public var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?
    public var onDetailsTap: ((DetailsNode) -> Void)?
    public var theme: Theme = .default

    public override func prepareForReuse() {
        super.prepareForReuse()
        hostedView?.removeFromSuperview()
        hostedView = nil
        onLinkTap = nil
        onCheckboxToggle = nil
        onDetailsTap = nil

        self.isAccessibilityElement = false
        self.accessibilityLabel = nil
        self.accessibilityValue = nil
        self.accessibilityHint = nil
        self.accessibilityTraits = .none
    }

    /// Mounts the pre-calculated `LayoutResult` onto the main thread.
    public func configure(with layout: LayoutResult) {
        switch layout.node {
        case is ImageNode:
            if let imageView = hostedView as? AsyncImageView {
                imageView.frame = CGRect(origin: .zero, size: layout.size)
                imageView.configure(with: layout)
            } else {
                hostedView?.removeFromSuperview()
                let imageView = AsyncImageView(frame: CGRect(origin: .zero, size: layout.size))
                self.contentView.addSubview(imageView)
                self.hostedView = imageView
                imageView.configure(with: layout)
            }

        case is CodeBlockNode, is DiagramNode:
            if let codeView = hostedView as? AsyncCodeView {
                codeView.frame = CGRect(origin: .zero, size: layout.size)
                codeView.configure(with: layout)
            } else {
                hostedView?.removeFromSuperview()
                let codeView = AsyncCodeView(frame: CGRect(origin: .zero, size: layout.size), theme: theme)
                self.contentView.addSubview(codeView)
                self.hostedView = codeView
                codeView.configure(with: layout)
            }

        default:
            // Text or generic block containers
            if let textView = hostedView as? AsyncTextView {
                textView.frame = CGRect(origin: .zero, size: layout.size)
                textView.theme = theme
                textView.onLinkTap = onLinkTap
                textView.onCheckboxToggle = onCheckboxToggle
                textView.configure(with: layout)
            } else {
                hostedView?.removeFromSuperview()
                let textView = AsyncTextView(frame: CGRect(origin: .zero, size: layout.size))
                textView.theme = theme
                textView.onLinkTap = onLinkTap
                textView.onCheckboxToggle = onCheckboxToggle
                self.contentView.addSubview(textView)
                self.hostedView = textView
                textView.configure(with: layout)
            }
        }

        // Configure Accessibility on the CollectionViewCell itself to allow
        // VoiceOver to read sequentially over the virtualized UI list.
        self.isAccessibilityElement = true
        self.accessibilityTraits = PlatformAccessibility.accessibilityTraits(for: layout)
        if let label = PlatformAccessibility.accessibilityLabel(for: layout) {
            self.accessibilityLabel = label
        }
        if let value = PlatformAccessibility.accessibilityValue(for: layout) {
            self.accessibilityValue = value
        }
        if let hint = PlatformAccessibility.accessibilityHint(for: layout) {
            self.accessibilityHint = hint
        }
    }
}
#endif
