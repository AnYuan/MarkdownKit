//
//  AsyncCodeView.swift
//  MarkdownKit
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// A Texture-inspired asynchronous native view specifically tailored for Code Blocks.
/// It wraps an `AsyncTextView` to perform actual text rendering, but manages its own
/// background layer for the block's background color and corner radius.
public class AsyncCodeView: UIView {
    
    private let textView = AsyncTextView(frame: .zero)
    private let copyButton = UIButton(type: .system)

    /// Forwards to the inner `AsyncTextView.displaysAsynchronously`.
    public var displaysAsynchronously: Bool {
        get { textView.displaysAsynchronously }
        set { textView.displaysAsynchronously = newValue }
    }

    private let theme: Theme
    private var rawCode: String = ""
    private var copyButtonDefaultImage: UIImage?
    private var copyFeedbackResetWorkItem: DispatchWorkItem?
    private var copyFeedbackGeneration = 0

    /// Internal dependency-injection seam for copy handling. Defaults to writing to
    /// `UIPasteboard.general`, but tests can substitute an in-memory sink to avoid
    /// touching the system pasteboard (which can block headlessly under XCTest).
    internal var copySink: (String) -> Void = { UIPasteboard.general.string = $0 }

    private var padding: CGFloat { theme.codeBlock.viewPadding }
    
    public init(frame: CGRect, theme: Theme = .default) {
        self.theme = theme
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        self.theme = .default
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        self.backgroundColor = theme.colors.codeColor.background
        self.layer.cornerRadius = theme.codeBlock.cornerRadius
        self.clipsToBounds = true
        
        addSubview(textView)
        
        // Configure native copy button
        setupCopyButton()
        addSubview(copyButton)
    }
    
    private func setupCopyButton() {
        let config = UIImage.SymbolConfiguration(pointSize: theme.codeBlock.copyButtonIconSize, weight: .semibold)
        let image = UIImage(systemName: "doc.on.doc", withConfiguration: config)
        copyButtonDefaultImage = image
        copyButton.setImage(image, for: .normal)
        copyButton.tintColor = .secondaryLabel
        copyButton.backgroundColor = theme.colors.codeColor.background.withAlphaComponent(0.8)
        copyButton.layer.cornerRadius = theme.codeBlock.copyButtonCornerRadius
        
        copyButton.addAction(UIAction { [weak self] _ in
            self?.executeCopy()
        }, for: .touchUpInside)
    }
    
    private func executeCopy() {
        guard !rawCode.isEmpty else { return }
        copySink(rawCode)
        resetCopyFeedback()
        
        // Feedback animation
        let checkImage = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: theme.codeBlock.copyButtonIconSize, weight: .bold))
        
        UIView.animate(withDuration: 0.2) {
            self.copyButton.setImage(checkImage, for: .normal)
            self.copyButton.tintColor = .systemGreen
        }

        let generation = copyFeedbackGeneration
        let resetWorkItem = DispatchWorkItem { [weak self] in
            guard let self, self.copyFeedbackGeneration == generation else { return }
            UIView.animate(withDuration: 0.2) {
                self.copyButton.setImage(self.copyButtonDefaultImage, for: .normal)
                self.copyButton.tintColor = .secondaryLabel
            }
            self.copyFeedbackResetWorkItem = nil
        }
        copyFeedbackResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: resetWorkItem)
    }

    private func resetCopyFeedback() {
        copyFeedbackResetWorkItem?.cancel()
        copyFeedbackResetWorkItem = nil
        copyFeedbackGeneration &+= 1
        copyButton.layer.removeAllAnimations()
        copyButton.setImage(copyButtonDefaultImage, for: .normal)
        copyButton.tintColor = .secondaryLabel
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        // Pin the internal async text view with padding
        textView.frame = bounds.insetBy(dx: padding, dy: padding)
        
        // Pin Copy button to top right
        let buttonSize = theme.codeBlock.copyButtonSize
        let buttonMargin = theme.codeBlock.copyButtonMargin
        copyButton.frame = CGRect(
            x: bounds.width - buttonSize - buttonMargin,
            y: buttonMargin,
            width: buttonSize,
            height: buttonSize
        )
    }
    
    /// Resets internal state so the view can be reused by a recycling cell.
    public func prepareForReuse() {
        resetCopyFeedback()
        rawCode = ""
        textView.prepareForReuse()
    }

    /// Binds the `LayoutResult` constraint to the view.
    public func configure(with layout: LayoutResult) {
        resetCopyFeedback()
        self.frame.size = layout.size
        
        // Pass the configuration down to the AsyncTextView to begin background text rasterization
        // We artificially adjust the internal layout result size to account for our padding 
        // to prevent clipping the background GPU drawing constraint.
        let insetSize = CGSize(
            width: max(0, layout.size.width - (padding * 2)), 
            height: max(0, layout.size.height - (padding * 2))
        )
        
        let insetLayout = LayoutResult(
            node: layout.node, 
            size: insetSize, 
            attributedString: layout.attributedString, 
            children: layout.children
        )
        
        if let codeNode = layout.node as? CodeBlockNode {
            self.rawCode = codeNode.code
        } else if let diagramNode = layout.node as? DiagramNode {
            self.rawCode = diagramNode.source
        } else {
            self.rawCode = ""
        }
        
        textView.configure(with: insetLayout)
    }
}
#endif
