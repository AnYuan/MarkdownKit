//
//  MarkdownCollectionView.swift
//  MarkdownKit
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

public protocol MarkdownCollectionViewThemeDelegate: AnyObject {
    func markdownCollectionViewDidRequestThemeReload(_ view: MarkdownCollectionView)
}

/// The core macOS rendering interface. This wraps an `NSCollectionView` tailored 
/// explicitly for extremely high-performance vertically scrolling text blocks.
public class MarkdownCollectionView: NSView {
    
    public weak var themeDelegate: MarkdownCollectionViewThemeDelegate?
    public var onToggleDetails: ((Int, DetailsNode) -> Void)?
    public var onToggleCheckbox: ((CheckboxInteractionData) -> Void)?
    
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    
    public var layouts: [LayoutResult] = [] {
        didSet {
            collectionView.reloadData()
        }
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // 1. Configure the Flow Layout
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.minimumLineSpacing = 12
        flowLayout.sectionInset = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        
        // 2. Configure the Collection View
        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColors = [.clear]
        collectionView.register(MarkdownItemView.self, forItemWithIdentifier: MarkdownItemView.reuseIdentifier)
        
        // 3. Configure the Scroll View Container
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        
        addSubview(scrollView)
    }
    
    public override func layout() {
        super.layout()
        scrollView.frame = bounds
        // Width dictates text wrapping; when view resizes, 
        // a new background LayoutSolver pass should be triggered externally.
    }
    
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        themeDelegate?.markdownCollectionViewDidRequestThemeReload(self)
    }
}

// MARK: - DataSource & Delegate
extension MarkdownCollectionView: NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    
    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return layouts.count
    }
    
    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: MarkdownItemView.reuseIdentifier, for: indexPath) as! MarkdownItemView
        
        let layoutResult = layouts[indexPath.item]
        item.configure(
            with: layoutResult,
            onToggleDetails: { [weak self] details in
                self?.onToggleDetails?(indexPath.item, details)
            },
            onCheckboxToggle: { [weak self] interactionData in
                self?.onToggleCheckbox?(interactionData)
            }
        )
        
        return item
    }
    
    // Crucial: The CollectionView instantaneous sizing query. 
    // Because LayoutResult measured this in the background, we return `CGSize` in O(1) time.
    public func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        let result = layouts[indexPath.item]
        // Lock to the exact width of the scrollview to prevent horizontal drifting, but use calculated height
        return NSSize(width: scrollView.contentSize.width, height: result.size.height)
    }
}
#endif
