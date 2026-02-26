//
//  MarkdownCollectionView.swift
//  MyMarkdown
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

public protocol MarkdownCollectionViewThemeDelegate: AnyObject {
    func markdownCollectionViewDidRequestThemeReload(_ view: MarkdownCollectionView)
}

/// The core iOS rendering interface. This wraps a `UICollectionView` tailored 
/// explicitly for extremely high-performance vertically scrolling text blocks.
public class MarkdownCollectionView: UIView {
    
    public weak var themeDelegate: MarkdownCollectionViewThemeDelegate?
    
    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        return cv
    }()
    
    public var layouts: [LayoutResult] = [] {
        didSet {
            collectionView.reloadData()
        }
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // 1. Configure the Flow Layout
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.minimumLineSpacing = 0
        flowLayout.sectionInset = .zero
        
        // 2. Configure the Collection View
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.register(MarkdownCollectionViewCell.self, forCellWithReuseIdentifier: MarkdownCollectionViewCell.reuseIdentifier)
        
        // 3. Add to View Hierarchy
        addSubview(collectionView)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds
        // Width dictates text wrapping; when view resizes, 
        // a new background LayoutSolver pass should be triggered externally.
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            themeDelegate?.markdownCollectionViewDidRequestThemeReload(self)
        }
    }
}

// MARK: - DataSource & Delegate
extension MarkdownCollectionView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return layouts.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MarkdownCollectionViewCell.reuseIdentifier, for: indexPath) as! MarkdownCollectionViewCell
        
        let layoutResult = layouts[indexPath.item]
        cell.configure(with: layoutResult)
        
        return cell
    }
    
    // Crucial: The CollectionView instantaneous sizing query. 
    // Because LayoutResult measured this in the background, we return `CGSize` in O(1) time.
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let result = layouts[indexPath.item]
        // Lock to the exact width of the scrollview to prevent horizontal drifting, but use calculated height
        return CGSize(width: collectionView.bounds.width, height: result.size.height)
    }
}
#endif
