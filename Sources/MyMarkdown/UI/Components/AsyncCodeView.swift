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
    private let theme: Theme
    
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
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        // Pin the internal async text view with padding
        textView.frame = bounds.insetBy(dx: padding, dy: padding)
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
        
        textView.configure(with: insetLayout)
    }
}
#endif
