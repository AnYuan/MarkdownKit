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
///
/// Cell management goes through an `NSCollectionViewDiffableDataSource` keyed
/// by `StableNodeIdentity`, so streaming updates trigger insert / delete /
/// move diffs instead of full `reloadData()`.
public class MarkdownCollectionView: NSView {

    public weak var themeDelegate: MarkdownCollectionViewThemeDelegate?
    public var onToggleDetails: ((Int, DetailsNode) -> Void)?
    public var onToggleCheckbox: ((CheckboxInteractionData) -> Void)?
    public var onLinkTap: ((URL) -> Void)?
    public var theme: Theme = .default
    public var textInteractionMode: MarkdownTextInteractionMode = .asyncReadOnly {
        didSet {
            guard oldValue != textInteractionMode else { return }
            reconfigureVisibleItems()
        }
    }
    var onEffectiveContentWidthChange: ((CGFloat) -> Void)? {
        didSet {
            reportEffectiveContentWidthIfNeeded(force: true)
        }
    }
    var effectiveContentWidth: CGFloat {
        let contentWidth = scrollView.contentSize.width
        return contentWidth > 0 ? contentWidth : bounds.width
    }

    private enum Section { case main }

    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private var lastReportedContentWidth: CGFloat = 0
    private var dataSource: NSCollectionViewDiffableDataSource<Section, StableNodeIdentity>!
    private var layoutsByIdentity: [StableNodeIdentity: LayoutResult] = [:]

    public var layouts: [LayoutResult] = [] {
        didSet {
            applyLayouts(layouts)
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
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.minimumLineSpacing = 12
        flowLayout.sectionInset = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        collectionView.collectionViewLayout = flowLayout
        collectionView.delegate = self
        collectionView.backgroundColors = [.clear]
        collectionView.register(MarkdownItemView.self, forItemWithIdentifier: MarkdownItemView.reuseIdentifier)

        dataSource = NSCollectionViewDiffableDataSource<Section, StableNodeIdentity>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, identity in
            guard let self,
                  let item = collectionView.makeItem(
                      withIdentifier: MarkdownItemView.reuseIdentifier,
                      for: indexPath
                  ) as? MarkdownItemView,
                  let layoutResult = self.layoutsByIdentity[identity] else {
                fatalError("Failed to dequeue MarkdownItemView or resolve layout for \(identity)")
            }

            item.preferredContainerWidth = self.effectiveContentWidth
            item.configure(
                with: layoutResult,
                theme: self.theme,
                textInteractionMode: self.textInteractionMode,
                onToggleDetails: { [weak self] details in
                    guard let self else { return }
                    let snapshot = self.dataSource.snapshot()
                    let snapshotIndex = snapshot.indexOfItem(identity) ?? indexPath.item
                    self.onToggleDetails?(snapshotIndex, details)
                },
                onCheckboxToggle: { [weak self] interactionData in
                    self?.onToggleCheckbox?(interactionData)
                },
                onLinkTap: { [weak self] url in
                    self?.onLinkTap?(url)
                }
            )
            return item
        }

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        addSubview(scrollView)
    }

    public override func layout() {
        super.layout()
        scrollView.frame = bounds
        reportEffectiveContentWidthIfNeeded()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        themeDelegate?.markdownCollectionViewDidRequestThemeReload(self)
    }

    // MARK: - Snapshot application

    private func applyLayouts(_ layouts: [LayoutResult]) {
        var lookup: [StableNodeIdentity: LayoutResult] = [:]
        lookup.reserveCapacity(layouts.count)
        for layout in layouts {
            lookup[layout.stableIdentity] = layout
        }
        layoutsByIdentity = lookup

        var snapshot = NSDiffableDataSourceSnapshot<Section, StableNodeIdentity>()
        snapshot.appendSections([.main])
        snapshot.appendItems(layouts.map(\.stableIdentity), toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func reconfigureVisibleItems() {
        let visible = collectionView.indexPathsForVisibleItems()
        guard !visible.isEmpty else { return }
        let identities = visible.compactMap { dataSource.itemIdentifier(for: $0) }
        guard !identities.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        // `reconfigureItems` isn't available in the older AppKit
        // diffable-snapshot API; `reloadItems` is equivalent for our
        // single-section use case (it re-runs the cell provider).
        snapshot.reloadItems(identities)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    fileprivate func layoutResult(forIndexPath indexPath: IndexPath) -> LayoutResult? {
        guard let identity = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return layoutsByIdentity[identity]
    }

    private func reportEffectiveContentWidthIfNeeded(force: Bool = false) {
        let width = effectiveContentWidth
        guard width > 50 else { return }
        guard force || abs(width - lastReportedContentWidth) > 0.5 else { return }

        lastReportedContentWidth = width
        onEffectiveContentWidthChange?(width)
    }
}

// MARK: - Delegate
extension MarkdownCollectionView: NSCollectionViewDelegateFlowLayout {

    public func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        let height = layoutResult(forIndexPath: indexPath)?.size.height ?? 0
        return NSSize(width: scrollView.contentSize.width, height: height)
    }
}
#endif
