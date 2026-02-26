//
//  AsyncCodeView.swift
//  MyMarkdown
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// A Texture-inspired asynchronous native view specifically tailored for Code Blocks.
/// It wraps an `AsyncTextView` to perform actual text rendering, but manages its own
/// background layer for the block's background color and corner radius.
public class AsyncCodeView: UIView {
    
    private let textView = AsyncTextView(frame: .zero)
    private let copyButton = UIButton(type: .system)
    
    private let theme: Theme
    private var rawCode: String = ""
    
    // Setup generic paddings. Production engine will read these from Theme Tokens.
    private let padding: CGFloat = 16.0 
    
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
        self.backgroundColor = theme.codeColor.background
        self.layer.cornerRadius = 8.0
        self.clipsToBounds = true
        
        addSubview(textView)
        
        // Configure native copy button
        setupCopyButton()
        addSubview(copyButton)
    }
    
    private func setupCopyButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = UIImage(systemName: "doc.on.doc", withConfiguration: config)
        copyButton.setImage(image, for: .normal)
        copyButton.tintColor = .secondaryLabel
        copyButton.backgroundColor = theme.codeColor.background.withAlphaComponent(0.8)
        copyButton.layer.cornerRadius = 6.0
        
        copyButton.addAction(UIAction { [weak self] _ in
            self?.executeCopy()
        }, for: .touchUpInside)
    }
    
    private func executeCopy() {
        guard !rawCode.isEmpty else { return }
        UIPasteboard.general.string = rawCode
        
        // Feedback animation
        let originalImage = copyButton.image(for: .normal)
        let checkImage = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        
        UIView.animate(withDuration: 0.2) {
            self.copyButton.setImage(checkImage, for: .normal)
            self.copyButton.tintColor = .systemGreen
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            UIView.animate(withDuration: 0.2) {
                self.copyButton.setImage(originalImage, for: .normal)
                self.copyButton.tintColor = .secondaryLabel
            }
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        // Pin the internal async text view with padding
        textView.frame = bounds.insetBy(dx: padding, dy: padding)
        
        // Pin Copy button to top right
        let buttonSize: CGFloat = 30
        copyButton.frame = CGRect(
            x: bounds.width - buttonSize - 8,
            y: 8,
            width: buttonSize,
            height: buttonSize
        )
    }
    
    /// Binds the `LayoutResult` constraint to the view.
    public func configure(with layout: LayoutResult) {
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
        }
        
        textView.configure(with: insetLayout)
    }
}
#endif
