//
//  MarkdownCollectionView.swift
//  MarkdownKit
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

public protocol MarkdownCollectionViewThemeDelegate: AnyObject {
    func markdownCollectionViewDidRequestThemeReload(_ view: MarkdownCollectionView)
}

/// The core iOS rendering interface. This wraps a `UICollectionView` tailored
/// explicitly for extremely high-performance vertically scrolling text blocks.
///
/// Cell management goes through a `UICollectionViewDiffableDataSource` keyed
/// by `StableNodeIdentity`, so streaming updates (e.g. ChatGPT token-by-token)
/// trigger insert / delete / move diffs instead of full `reloadData()`.
public class MarkdownCollectionView: UIView {

    public weak var themeDelegate: MarkdownCollectionViewThemeDelegate?
    public var onToggleDetails: ((Int, DetailsNode) -> Void)?
    public var onLinkTap: ((URL) -> Void)?
    public var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?
    public var theme: Theme = .default
    public var imageLoadingPolicy: ImageLoadingPolicy = .default {
        didSet {
            guard oldValue != imageLoadingPolicy else { return }
            // Visible-only reconfigure beats `reloadData()` here — the policy
            // affects image rendering, not layout geometry, so cells offscreen
            // can wait until next dequeue.
            reconfigureVisibleItems()
        }
    }
    public var textInteractionMode: MarkdownTextInteractionMode = .asyncReadOnly {
        didSet {
            guard oldValue != textInteractionMode else { return }
            reconfigureVisibleItems()
        }
    }

    private enum Section { case main }

    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        return cv
    }()
    private var dataSource: UICollectionViewDiffableDataSource<Section, StableNodeIdentity>!

    /// Identity → LayoutResult lookup. Built once per `layouts` setter to keep
    /// `cellForItemAt` and `sizeForItemAt` O(1) without hitting the array
    /// every time.
    private var layoutsByIdentity: [StableNodeIdentity: LayoutResult] = [:]

    /// Track in-flight prefetch tasks so we can cancel them when the user
    /// scrolls past the prefetched region before they appear on-screen.
    private var prefetchTasks: [IndexPath: Task<Void, Never>] = [:]

    public var layouts: [LayoutResult] = [] {
        didSet {
            applyLayouts(layouts)
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
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.minimumLineSpacing = 0
        flowLayout.sectionInset = .zero

        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.backgroundColor = .clear
        collectionView.register(MarkdownCollectionViewCell.self, forCellWithReuseIdentifier: MarkdownCollectionViewCell.reuseIdentifier)

        dataSource = UICollectionViewDiffableDataSource<Section, StableNodeIdentity>(
            collectionView: collectionView
        ) { [weak self] _, indexPath, identity in
            guard let self,
                  let cell = self.collectionView.dequeueReusableCell(
                      withReuseIdentifier: MarkdownCollectionViewCell.reuseIdentifier,
                      for: indexPath
                  ) as? MarkdownCollectionViewCell,
                  let layoutResult = self.layoutsByIdentity[identity] else {
                fatalError("Failed to dequeue MarkdownCollectionViewCell or resolve layout for \(identity)")
            }

            cell.theme = self.theme
            cell.onLinkTap = self.onLinkTap
            cell.onCheckboxToggle = self.onCheckboxToggle
            cell.textInteractionMode = self.textInteractionMode
            cell.imageLoadingPolicy = self.imageLoadingPolicy
            cell.onDetailsTap = { [weak self] details in
                // Resolve index from the live snapshot so external callers
                // get the current position even if the cell moved.
                guard let self else { return }
                let snapshot = self.dataSource.snapshot()
                let snapshotIndex = snapshot.indexOfItem(identity) ?? indexPath.item
                self.onToggleDetails?(snapshotIndex, details)
            }

            cell.configure(with: layoutResult)
            return cell
        }

        addSubview(collectionView)

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (view: MarkdownCollectionView, _) in
            self?.themeDelegate?.markdownCollectionViewDidRequestThemeReload(view)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds
    }

    // MARK: - Snapshot application

    private func applyLayouts(_ layouts: [LayoutResult]) {
        // Build the lookup before applying the snapshot — the data source's
        // cell provider may immediately try to resolve identities.
        var lookup: [StableNodeIdentity: LayoutResult] = [:]
        lookup.reserveCapacity(layouts.count)
        for layout in layouts {
            lookup[layout.stableIdentity] = layout
        }
        layoutsByIdentity = lookup

        var snapshot = NSDiffableDataSourceSnapshot<Section, StableNodeIdentity>()
        snapshot.appendSections([.main])
        snapshot.appendItems(layouts.map(\.stableIdentity), toSection: .main)
        // animatingDifferences: false — streaming updates would otherwise
        // flicker. Hosts that want animations can tweak this later.
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func reconfigureVisibleItems() {
        let visible = collectionView.indexPathsForVisibleItems
        guard !visible.isEmpty else { return }
        let identities = visible.compactMap { dataSource.itemIdentifier(for: $0) }
        guard !identities.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(identities)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    fileprivate func layoutResult(forIndexPath indexPath: IndexPath) -> LayoutResult? {
        guard let identity = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return layoutsByIdentity[identity]
    }
}

// MARK: - Layout / prefetch delegate
extension MarkdownCollectionView: UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {

    // Sizing stays O(1): `LayoutResult.size` was measured in the background.
    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let height = layoutResult(forIndexPath: indexPath)?.size.height ?? 0
        return CGSize(width: collectionView.bounds.width, height: height)
    }

    // Warm up the rasterization cache for cells about to scroll into view so
    // the bitmap is ready by the time the cell is dequeued, eliminating the
    // first-paint frame stall.
    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard prefetchTasks[indexPath] == nil,
                  let layoutResult = layoutResult(forIndexPath: indexPath) else { continue }

            let task = AsyncTextView.preheat(layoutResult)
            prefetchTasks[indexPath] = task
        }
    }

    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            prefetchTasks.removeValue(forKey: indexPath)?.cancel()
        }
    }
}
#endif
