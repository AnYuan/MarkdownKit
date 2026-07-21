//
//  MarkdownCollectionViewCell.swift
//  MarkdownKit
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// A highly reusable, recycled view cell managed by `UICollectionView`.
/// Its sole responsibility is mounting the pre-calculated `LayoutResult`
/// and displaying the dynamically generated background `CGImage` or `CGContext` snapshots.
class MarkdownCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "MarkdownCollectionViewCell"

    /// The specific view container responsible for rendering the assigned AST element.
    private var hostedView: UIView?

    // MARK: - Interaction Callbacks (set by collection view before configure)

    var onLinkTap: ((URL) -> Void)?
    var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?
    var onDetailsTap: ((DetailsNode) -> Void)?
    var theme: Theme = .default
    var textInteractionMode: MarkdownTextInteractionMode = .asyncReadOnly {
        didSet {
            guard oldValue != textInteractionMode,
                  let currentLayout,
                  Self.shouldUseSelectableTextView(
                    for: currentLayout,
                    mode: textInteractionMode
                  ) else {
                return
            }
            cancelHostedRasterRendering()
        }
    }
    var rasterPipeline: RasterImagePipeline = .shared {
        didSet {
            guard oldValue !== rasterPipeline else { return }
            applyRasterDependencies(to: hostedView)
        }
    }
    var resolvedDisplayScale: CGFloat? {
        didSet {
            guard oldValue != resolvedDisplayScale else { return }
            applyRasterDependencies(to: hostedView)
        }
    }

    private var currentLayout: LayoutResult?

    var rasterPipelineForTesting: RasterImagePipeline? {
        get { rasterPipeline }
        set { rasterPipeline = newValue ?? .shared }
    }

    var displayScaleOverrideForTesting: CGFloat? {
        get { resolvedDisplayScale }
        set { resolvedDisplayScale = newValue }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil {
            cancelHostedRasterRendering()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Keep the hosted code/text view alive across recycles and reset its
        // state in place so cell pooling also reuses the expensive inner view.
        switch hostedView {
        case let codeView as AsyncCodeView:
            codeView.prepareForReuse()
        case let textView as AsyncTextView:
            textView.prepareForReuse()
        case let selectableTextView as SelectableTextView:
            selectableTextView.prepareForReuse()
        default:
            break
        }
        onLinkTap = nil
        onCheckboxToggle = nil
        onDetailsTap = nil
        currentLayout = nil

        self.isAccessibilityElement = false
        self.accessibilityLabel = nil
        self.accessibilityValue = nil
        self.accessibilityHint = nil
        self.accessibilityTraits = .none
    }

    /// Mounts the pre-calculated `LayoutResult` onto the main thread.
    func configure(with layout: LayoutResult) {
        currentLayout = layout
        switch layout.node {
        case is CodeBlockNode, is DiagramNode:
            if let codeView = hostedView as? AsyncCodeView {
                codeView.frame = CGRect(origin: .zero, size: layout.size)
                applyRasterDependencies(to: codeView)
                codeView.configure(with: layout, theme: theme)
            } else {
                removeHostedView()
                let codeView = AsyncCodeView(frame: CGRect(origin: .zero, size: layout.size), theme: theme)
                applyRasterDependencies(to: codeView)
                self.contentView.addSubview(codeView)
                self.hostedView = codeView
                codeView.configure(with: layout, theme: theme)
            }

        default:
            // Text or generic block containers
            if shouldUseSelectableTextView(for: layout) {
                if let textView = hostedView as? SelectableTextView {
                    textView.frame = CGRect(origin: .zero, size: layout.size)
                    textView.onLinkTap = onLinkTap
                    textView.onCheckboxToggle = onCheckboxToggle
                    textView.configure(with: layout)
                } else {
                    removeHostedView()
                    let textView = SelectableTextView(frame: CGRect(origin: .zero, size: layout.size))
                    textView.isAccessibilityElement = false
                    textView.onLinkTap = onLinkTap
                    textView.onCheckboxToggle = onCheckboxToggle
                    self.contentView.addSubview(textView)
                    self.hostedView = textView
                    textView.configure(with: layout)
                }
            } else if let textView = hostedView as? AsyncTextView {
                textView.frame = CGRect(origin: .zero, size: layout.size)
                applyRasterDependencies(to: textView)
                textView.theme = theme
                textView.onLinkTap = onLinkTap
                textView.onCheckboxToggle = onCheckboxToggle
                textView.configure(with: layout)
            } else {
                removeHostedView()
                let textView = AsyncTextView(frame: CGRect(origin: .zero, size: layout.size))
                applyRasterDependencies(to: textView)
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

    private func shouldUseSelectableTextView(for layout: LayoutResult) -> Bool {
        Self.shouldUseSelectableTextView(for: layout, mode: textInteractionMode)
    }

    static func shouldUseSelectableTextView(
        for layout: LayoutResult,
        mode: MarkdownTextInteractionMode
    ) -> Bool {
        mode == .selectableNative
            && !(layout.node is CodeBlockNode)
            && !(layout.node is DiagramNode)
            && layout.customDraw == nil
            && layout.attributedString?.length ?? 0 > 0
    }

    func cancelHostedRasterRendering() {
        switch hostedView {
        case let codeView as AsyncCodeView:
            codeView.cancelRendering()
        case let textView as AsyncTextView:
            textView.cancelRendering()
        default:
            break
        }
    }

    private func applyRasterDependencies(to view: UIView?) {
        switch view {
        case let codeView as AsyncCodeView:
            codeView.rasterPipeline = rasterPipeline
            codeView.displayScaleOverride = resolvedDisplayScale
        case let textView as AsyncTextView:
            textView.rasterPipeline = rasterPipeline
            textView.displayScaleOverride = resolvedDisplayScale
        default:
            break
        }
    }

    private func removeHostedView() {
        cancelHostedRasterRendering()
        if let selectableTextView = hostedView as? SelectableTextView {
            selectableTextView.prepareForReuse()
        }
        hostedView?.removeFromSuperview()
        hostedView = nil
    }
}
#endif
