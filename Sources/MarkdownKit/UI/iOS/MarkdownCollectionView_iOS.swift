//
//  MarkdownCollectionView.swift
//  MarkdownKit
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

public protocol MarkdownCollectionViewThemeDelegate: AnyObject {
    func markdownCollectionViewDidRequestThemeReload(_ view: MarkdownCollectionView)
}

struct RasterPrefetchRecord {
    let indexPath: IndexPath
    let stableIdentity: StableNodeIdentity
    let key: RasterRenderKey
    let token: UUID
    let lease: RasterImageLease
    let pipelineIdentifier: ObjectIdentifier
    var completionTask: Task<Void, Never>?

    var leaseGeneration: Int {
        lease.generation
    }
}

/// The core iOS rendering interface. This wraps a `UICollectionView` tailored
/// explicitly for extremely high-performance vertically scrolling text blocks.
///
/// Cell management goes through a `UICollectionViewDiffableDataSource` keyed
/// by a module-owned stable item identity, so streaming updates (e.g. ChatGPT
/// token-by-token) trigger insert / delete / move diffs instead of full
/// `reloadData()`.
public class MarkdownCollectionView: UIView {

    public weak var themeDelegate: MarkdownCollectionViewThemeDelegate?
    public var onToggleDetails: ((Int, DetailsNode) -> Void)?
    public var onLinkTap: ((URL) -> Void)?
    public var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?
    public var theme: Theme = .default
    public var textInteractionMode: MarkdownTextInteractionMode = .asyncReadOnly {
        didSet {
            guard oldValue != textInteractionMode else { return }
            reconcileRasterPrefetchRecords()
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

    private var rasterPrefetchRecords: [IndexPath: RasterPrefetchRecord] = [:]
    private var currentDisplayScale: CGFloat = 2

    var rasterPipelineForTesting: RasterImagePipeline? {
        didSet {
            guard oldValue !== rasterPipelineForTesting else { return }
            cancelAllRasterPrefetchRecords()
            applyRasterDependenciesToVisibleCells()
        }
    }

    var displayScaleOverrideForTesting: CGFloat? {
        didSet {
            refreshDisplayScale()
        }
    }

    var rasterPrefetchRecordsForTesting: [IndexPath: RasterPrefetchRecord] {
        rasterPrefetchRecords
    }

    private(set) var layoutSnapshotApplicationCountForTesting = 0
    private(set) var layoutSnapshotSkipCountForTesting = 0
    private(set) var lastLayoutChangedIdentityCountForTesting = 0
    private(set) var layoutInvalidationRequestCountForTesting = 0
    var onLayoutSnapshotApplicationCompletionForTesting: (() -> Void)?

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

    isolated deinit {
        cancelAllRasterPrefetchRecords()
    }

    private func setup() {
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.minimumLineSpacing = 0
        flowLayout.sectionInset = .zero

        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.backgroundColor = .clear
        collectionView.register(MarkdownCollectionViewCell.self, forCellWithReuseIdentifier: MarkdownCollectionViewCell.reuseIdentifier)
        currentDisplayScale = resolveDisplayScale()

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
            cell.onLinkTap = { [weak self] url in
                if let handler = self?.onLinkTap {
                    handler(url)
                } else {
                    UIApplication.shared.open(url)
                }
            }
            cell.onCheckboxToggle = { [weak self] interactionData in
                self?.onCheckboxToggle?(interactionData)
            }
            cell.textInteractionMode = self.textInteractionMode
            cell.rasterPipeline = self.rasterPipeline
            cell.resolvedDisplayScale = self.currentDisplayScale
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
        registerForTraitChanges([UITraitDisplayScale.self]) {
            (view: MarkdownCollectionView, _) in
            view.refreshDisplayScale()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds
    }

    // MARK: - Snapshot application

    private func applyLayouts(_ layouts: [LayoutResult]) {
        let currentSnapshot = dataSource.snapshot()
        let hasMainSection = currentSnapshot.sectionIdentifiers.contains(.main)
        let plan = LayoutCollectionUpdatePlan(
            layouts: layouts,
            previousLayoutsByIdentity: layoutsByIdentity,
            currentOrderedIdentities: hasMainSection
                ? currentSnapshot.itemIdentifiers(inSection: .main)
                : [],
            hasMainSection: hasMainSection
        )

        layoutsByIdentity = plan.layoutsByIdentity
        reconcileRasterPrefetchRecords(orderedIdentities: plan.orderedIdentities)
        lastLayoutChangedIdentityCountForTesting = plan.changedRetainedIdentities.count

        guard plan.requiresSnapshotApplication else {
            layoutSnapshotSkipCountForTesting += 1
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, StableNodeIdentity>()
        snapshot.appendSections([.main])
        snapshot.appendItems(plan.orderedIdentities, toSection: .main)
        snapshot.reconfigureItems(plan.changedRetainedIdentities)
        // animatingDifferences: false — streaming updates would otherwise
        // flicker. Hosts that want animations can tweak this later.
        let hasRetainedSizeChange = plan.hasRetainedSizeChange
        layoutSnapshotApplicationCountForTesting += 1
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            if hasRetainedSizeChange {
                self.layoutInvalidationRequestCountForTesting += 1
                self.flowLayout.invalidateLayout()
            }
            self.onLayoutSnapshotApplicationCompletionForTesting?()
        }
    }

    private func reconfigureVisibleItems() {
        let visible = collectionView.indexPathsForVisibleItems
        guard !visible.isEmpty else { return }
        for indexPath in visible {
            (collectionView.cellForItem(at: indexPath) as? MarkdownCollectionViewCell)?
                .textInteractionMode = textInteractionMode
        }
        let identities = visible.compactMap { dataSource.itemIdentifier(for: $0) }
        guard !identities.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(identities)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func layoutResult(forIndexPath indexPath: IndexPath) -> LayoutResult? {
        guard let identity = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return layoutsByIdentity[identity]
    }

    func drainRasterPrefetchCompletionsForTesting() async {
        let tasks = rasterPrefetchRecords.values.compactMap(\.completionTask)
        for task in tasks {
            await task.value
        }
    }

    private var rasterPipeline: RasterImagePipeline {
        rasterPipelineForTesting ?? .shared
    }

    private func resolveDisplayScale() -> CGFloat {
        if let displayScaleOverrideForTesting,
           displayScaleOverrideForTesting.isFinite,
           displayScaleOverrideForTesting > 0 {
            return displayScaleOverrideForTesting
        }
        if let scale = window?.windowScene?.screen.scale, scale > 0 {
            return scale
        }
        let traitScale = traitCollection.displayScale
        return traitScale > 0 ? traitScale : 2
    }

    private func refreshDisplayScale() {
        let scale = resolveDisplayScale()
        guard scale != currentDisplayScale else { return }
        currentDisplayScale = scale
        reconcileRasterPrefetchRecords()
        applyRasterDependenciesToVisibleCells()
    }

    private func applyRasterDependenciesToVisibleCells() {
        for case let cell as MarkdownCollectionViewCell in collectionView.visibleCells {
            cell.rasterPipeline = rasterPipeline
            cell.resolvedDisplayScale = currentDisplayScale
        }
    }

    private func currentOrderedIdentities() -> [StableNodeIdentity] {
        let snapshot = dataSource.snapshot()
        guard snapshot.sectionIdentifiers.contains(.main) else { return [] }
        return snapshot.itemIdentifiers(inSection: .main)
    }

    private func rasterKey(for layout: LayoutResult) -> RasterRenderKey? {
        rasterContentLayout(for: layout)?
            .rasterKey(displayScale: currentDisplayScale)
    }

    private func rasterContentLayout(for layout: LayoutResult) -> RasterContentLayout? {
        guard !MarkdownCollectionViewCell.shouldUseSelectableTextView(
            for: layout,
            mode: textInteractionMode
        ) else {
            return nil
        }
        return RasterContentLayout.resolve(layout: layout, theme: theme)
    }

    private func reconcileRasterPrefetchRecords(
        orderedIdentities: [StableNodeIdentity]? = nil
    ) {
        let identities = orderedIdentities ?? currentOrderedIdentities()
        let pipelineIdentifier = ObjectIdentifier(rasterPipeline)

        for (indexPath, record) in Array(rasterPrefetchRecords) {
            guard indexPath.section == 0,
                  identities.indices.contains(indexPath.item) else {
                cancelRasterPrefetchRecord(at: indexPath)
                continue
            }

            let identity = identities[indexPath.item]
            guard identity == record.stableIdentity,
                  record.pipelineIdentifier == pipelineIdentifier,
                  let layout = layoutsByIdentity[identity],
                  rasterKey(for: layout) == record.key else {
                cancelRasterPrefetchRecord(at: indexPath)
                continue
            }
        }
    }

    private func completeRasterPrefetch(
        indexPath: IndexPath,
        stableIdentity: StableNodeIdentity,
        key: RasterRenderKey,
        token: UUID,
        leaseGeneration: Int
    ) {
        guard let record = rasterPrefetchRecords[indexPath],
              record.indexPath == indexPath,
              record.stableIdentity == stableIdentity,
              record.key == key,
              record.token == token,
              record.leaseGeneration == leaseGeneration else {
            return
        }
        rasterPrefetchRecords.removeValue(forKey: indexPath)
    }

    private func cancelRasterPrefetchRecord(at indexPath: IndexPath) {
        guard let record = rasterPrefetchRecords.removeValue(forKey: indexPath) else {
            return
        }
        record.completionTask?.cancel()
        record.lease.release()
    }

    private func cancelAllRasterPrefetchRecords() {
        let indexPaths = Array(rasterPrefetchRecords.keys)
        for indexPath in indexPaths {
            cancelRasterPrefetchRecord(at: indexPath)
        }
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
            guard let stableIdentity = dataSource.itemIdentifier(for: indexPath),
                  let layoutResult = layoutsByIdentity[stableIdentity],
                  let contentLayout = rasterContentLayout(for: layoutResult),
                  let key = contentLayout.rasterKey(displayScale: currentDisplayScale) else {
                continue
            }

            if let existingRecord = rasterPrefetchRecords[indexPath] {
                if existingRecord.stableIdentity == stableIdentity,
                   existingRecord.key == key,
                   existingRecord.pipelineIdentifier == ObjectIdentifier(rasterPipeline) {
                    continue
                }
                cancelRasterPrefetchRecord(at: indexPath)
            }

            guard let request = contentLayout.rasterRequest(
                displayScale: currentDisplayScale,
                priority: .utility
            ) else {
                continue
            }

            let token = UUID()
            let pipelineIdentifier = ObjectIdentifier(rasterPipeline)
            guard case let .pending(lease) = rasterPipeline.acquire(request) else {
                continue
            }

            let leaseGeneration = lease.generation
            rasterPrefetchRecords[indexPath] = RasterPrefetchRecord(
                indexPath: indexPath,
                stableIdentity: stableIdentity,
                key: key,
                token: token,
                lease: lease,
                pipelineIdentifier: pipelineIdentifier,
                completionTask: nil
            )

            let completionTask = Task { [weak self] in
                _ = await lease.value()
                lease.release()
                guard !Task.isCancelled else { return }
                self?.completeRasterPrefetch(
                    indexPath: indexPath,
                    stableIdentity: stableIdentity,
                    key: key,
                    token: token,
                    leaseGeneration: leaseGeneration
                )
            }
            rasterPrefetchRecords[indexPath]?.completionTask = completionTask
        }
    }

    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            cancelRasterPrefetchRecord(at: indexPath)
        }
    }
}
#endif
