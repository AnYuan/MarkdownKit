#if canImport(SwiftUI)
import SwiftUI

@available(iOS 14.0, macOS 11.0, *)
@MainActor
final class MarkdownEngine: ObservableObject {
    @Published var layouts: [LayoutResult] = []

    private static let debounceDelayNanoseconds: UInt64 = 200_000_000

    private var currentWidth: CGFloat = 0
    private var hasKnownEffectiveWidth = false

    private var latestConfiguration: MarkdownRenderConfiguration?
    private var committedParseKey: MarkdownParseKey?

    private var disclosureOverrides: [DetailsOverrideKey: Bool] = [:]
    private var cachedRawAST: CachedRawAST?

    private var generationCounter: UInt64 = 0
    private var latestGeneration: UInt64 = 0
    private var pendingRequest: RenderRequest?
    private var activeRenderTask: Task<RenderOutput, Never>?
    private var renderLoopTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    /// Persistent layout cache shared across renders. Without this, streaming /
    /// per-keystroke re-renders create a fresh LayoutSolver (hence fresh cache)
    /// and identical un-changed blocks are re-laid out every time.
    private let layoutCache = LayoutCache()

    /// Cached LayoutSolver reused while theme / diagram registry / image policy
    /// stay unchanged. Recreating a solver when those *do* change is correct
    /// because the variant hash they feed into would also change — old cache
    /// entries simply don't match and sit until evicted.
    private var cachedSolver: LayoutSolver?
    private var cachedSolverKey: SolverKey?

    private struct SolverKey: Equatable {
        let themeFingerprint: Int
        let diagramFingerprint: Int
        let policyFingerprint: Int
        let appearance: MarkdownAppearance
    }

    func preferredWidth(fallback: CGFloat) -> CGFloat {
        currentWidth > 50 ? currentWidth : fallback
    }

    func renderForCurrentPlatform(
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme,
        fallbackWidth: CGFloat,
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy,
        resourceLimits: MarkdownParser.ResourceLimits,
        appearance: MarkdownAppearance
    ) {
        let resolvedWidth = resolvedRenderWidth(fallbackWidth: fallbackWidth)
        let configuration = makeConfiguration(
            markdown: markdown,
            plugins: plugins,
            theme: theme,
            width: resolvedWidth ?? fallbackWidth,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy,
            resourceLimits: resourceLimits,
            appearance: appearance
        )
        storeLatestConfiguration(configuration)
        guard let resolvedWidth else { return }
        submitImmediate(configuration.withWidth(resolvedWidth))
    }

    func scheduleDebouncedRender(
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme,
        fallbackWidth: CGFloat,
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy,
        resourceLimits: MarkdownParser.ResourceLimits,
        appearance: MarkdownAppearance
    ) {
        let resolvedWidth = resolvedRenderWidth(fallbackWidth: fallbackWidth)
        let configuration = makeConfiguration(
            markdown: markdown,
            plugins: plugins,
            theme: theme,
            width: resolvedWidth ?? fallbackWidth,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy,
            resourceLimits: resourceLimits,
            appearance: appearance
        )
        scheduleDebounced(configuration: configuration, shouldSubmitAfterDelay: resolvedWidth != nil)
    }

    func updateEffectiveContentWidth(
        _ width: CGFloat,
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme,
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy,
        resourceLimits: MarkdownParser.ResourceLimits,
        appearance: MarkdownAppearance
    ) {
        guard width > 50 else { return }
        guard abs(width - currentWidth) > 0.5 else { return }

        currentWidth = width

        let configuration = makeConfiguration(
            markdown: markdown,
            plugins: plugins,
            theme: theme,
            width: width,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy,
            resourceLimits: resourceLimits,
            appearance: appearance
        )

        if !hasKnownEffectiveWidth {
            hasKnownEffectiveWidth = true
            submitImmediate(configuration)
            return
        }

        scheduleDebounced(configuration: configuration, shouldSubmitAfterDelay: true)
    }

    func toggleDetails(at index: Int, details: DetailsNode) {
        guard let latestConfiguration,
              let committedParseKey,
              latestConfiguration.parseKey == committedParseKey else { return }

        let key = DetailsOverrideKey(index: index, details: details)
        let desiredOpenState = !details.isOpen
        if let cachedRawAST,
           cachedRawAST.parseKey == committedParseKey,
           cachedRawAST.document.children.indices.contains(index),
           let rawDetails = cachedRawAST.document.children[index] as? DetailsNode,
           DetailsOverrideKey(index: index, details: rawDetails) == key,
           rawDetails.isOpen == desiredOpenState {
            disclosureOverrides.removeValue(forKey: key)
        } else {
            disclosureOverrides[key] = desiredOpenState
        }

        cancelDebounceTask()
        submitLatestConfigurationImmediately()
    }

    func waitUntilSettled() async {
        while true {
            let debounceTask = self.debounceTask
            let renderLoopTask = self.renderLoopTask

            if debounceTask == nil,
               renderLoopTask == nil,
               activeRenderTask == nil,
               pendingRequest == nil {
                return
            }

            if let debounceTask {
                _ = await debounceTask.result
            }
            if let renderLoopTask {
                _ = await renderLoopTask.result
            }
            await Task.yield()
        }
    }

    private func resolvedRenderWidth(fallbackWidth: CGFloat) -> CGFloat? {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        guard hasKnownEffectiveWidth, currentWidth > 50 else { return nil }
        return currentWidth
        #else
        let width = preferredWidth(fallback: fallbackWidth)
        return width > 50 ? width : nil
        #endif
    }

    private func makeConfiguration(
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme,
        width: CGFloat,
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy,
        resourceLimits: MarkdownParser.ResourceLimits,
        appearance: MarkdownAppearance
    ) -> MarkdownRenderConfiguration {
        MarkdownRenderConfiguration(
            parseKey: MarkdownParseKey(text: markdown, resourceLimits: resourceLimits, plugins: plugins),
            theme: theme,
            plugins: plugins,
            width: width,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy,
            appearance: appearance
        )
    }

    private func storeLatestConfiguration(_ configuration: MarkdownRenderConfiguration) {
        if latestConfiguration?.parseKey != configuration.parseKey {
            disclosureOverrides.removeAll()
        }
        latestConfiguration = configuration
    }

    private func scheduleDebounced(
        configuration: MarkdownRenderConfiguration,
        shouldSubmitAfterDelay: Bool
    ) {
        storeLatestConfiguration(configuration)
        invalidateActiveAndPendingGenerations()
        cancelDebounceTask()

        guard shouldSubmitAfterDelay else { return }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceDelayNanoseconds)
            guard !Task.isCancelled else { return }
            self?.submitDebouncedLatestConfiguration()
        }
    }

    private func submitDebouncedLatestConfiguration() {
        debounceTask = nil
        guard let latestConfiguration else { return }
        submitRequest(latestConfiguration)
    }

    private func submitLatestConfigurationImmediately() {
        guard let latestConfiguration else { return }
        submitImmediate(latestConfiguration)
    }

    private func submitImmediate(_ configuration: MarkdownRenderConfiguration) {
        cancelDebounceTask()
        storeLatestConfiguration(configuration)
        submitRequest(configuration)
    }

    private func submitRequest(_ configuration: MarkdownRenderConfiguration) {
        guard configuration.width > 50 else { return }

        let generation = nextGeneration()
        pendingRequest = RenderRequest(generation: generation, configuration: configuration)

        // Active work must fully return before the replacement request can start.
        activeRenderTask?.cancel()
        startRenderLoopIfNeeded()
    }

    private func invalidateActiveAndPendingGenerations() {
        _ = nextGeneration()
        pendingRequest = nil
        activeRenderTask?.cancel()
    }

    @discardableResult
    private func nextGeneration() -> UInt64 {
        generationCounter &+= 1
        latestGeneration = generationCounter
        return generationCounter
    }

    private func startRenderLoopIfNeeded() {
        guard renderLoopTask == nil else { return }
        renderLoopTask = Task { [weak self] in
            await self?.drainRenderLoop()
        }
    }

    private func drainRenderLoop() async {
        while let request = pendingRequest {
            pendingRequest = nil

            let work = prepareWork(for: request)
            let detached = Task.detached(priority: .userInitiated) {
                await Self.renderOffMain(work)
            }
            activeRenderTask = detached

            let output = await detached.value
            activeRenderTask = nil

            consume(output)
        }

        renderLoopTask = nil
    }

    private func prepareWork(for request: RenderRequest) -> RenderWork {
        let rawASTPreparation: RawASTPreparation
        if let cachedRawAST, cachedRawAST.parseKey == request.configuration.parseKey {
            rawASTPreparation = .reuse(cachedRawAST.document)
        } else {
            rawASTPreparation = .parse
        }

        return RenderWork(
            generation: request.generation,
            parseKey: request.configuration.parseKey,
            markdown: request.configuration.markdown,
            plugins: request.configuration.plugins,
            resourceLimits: request.configuration.resourceLimits,
            rawASTPreparation: rawASTPreparation,
            solver: solver(
                for: request.configuration.theme,
                diagramRegistry: request.configuration.diagramRegistry,
                imageLoadingPolicy: request.configuration.imageLoadingPolicy,
                appearance: request.configuration.appearance
            ),
            width: request.configuration.width,
            disclosureOverrides: disclosureOverrides
        )
    }

    private func consume(_ output: RenderOutput) {
        cachedRawAST = CachedRawAST(parseKey: output.parseKey, document: output.rawAST)

        guard output.generation == latestGeneration else { return }
        guard let childLayouts = output.childLayouts else { return }

        layouts = childLayouts
        committedParseKey = output.parseKey
    }

    private func solver(
        for theme: Theme,
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy,
        appearance: MarkdownAppearance
    ) -> LayoutSolver {
        let key = SolverKey(
            themeFingerprint: MarkdownRenderInput.themeFingerprint(theme, appearance: appearance),
            diagramFingerprint: diagramRegistry.cacheFingerprint,
            policyFingerprint: imageLoadingPolicy.cacheFingerprint,
            appearance: appearance
        )
        if let cachedSolver, cachedSolverKey == key {
            return cachedSolver
        }

        let solver = LayoutSolver(
            theme: theme,
            cache: layoutCache,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy,
            appearance: appearance
        )
        cachedSolver = solver
        cachedSolverKey = key
        return solver
    }

    private nonisolated static func renderOffMain(_ work: RenderWork) async -> RenderOutput {
        let rawAST: DocumentNode
        switch work.rawASTPreparation {
        case .reuse(let cachedRawAST):
            rawAST = cachedRawAST
        case .parse:
            let parser = MarkdownParser(plugins: work.plugins, limits: work.resourceLimits)
            rawAST = parser.parse(work.markdown)
        }

        if Task.isCancelled {
            return RenderOutput(
                generation: work.generation,
                parseKey: work.parseKey,
                rawAST: rawAST,
                childLayouts: nil
            )
        }

        let astForLayout = applyingDisclosureOverrides(work.disclosureOverrides, to: rawAST)
        let result = await work.solver.solve(node: astForLayout, constrainedToWidth: work.width)

        if Task.isCancelled {
            return RenderOutput(
                generation: work.generation,
                parseKey: work.parseKey,
                rawAST: rawAST,
                childLayouts: nil
            )
        }

        return RenderOutput(
            generation: work.generation,
            parseKey: work.parseKey,
            rawAST: rawAST,
            childLayouts: result.children
        )
    }

    private nonisolated static func applyingDisclosureOverrides(
        _ overrides: [DetailsOverrideKey: Bool],
        to document: DocumentNode
    ) -> DocumentNode {
        guard !overrides.isEmpty else { return document }

        var updatedChildren = document.children
        var didChange = false

        for (index, child) in updatedChildren.enumerated() {
            guard let details = child as? DetailsNode else { continue }

            let key = DetailsOverrideKey(index: index, details: details)
            guard let desiredOpenState = overrides[key], desiredOpenState != details.isOpen else {
                continue
            }

            updatedChildren[index] = DetailsNode(
                range: details.range,
                isOpen: desiredOpenState,
                summary: details.summary,
                children: details.children
            )
            didChange = true
        }

        guard didChange else { return document }
        return DocumentNode(range: document.range, children: updatedChildren)
    }

    private func cancelDebounceTask() {
        debounceTask?.cancel()
        debounceTask = nil
    }
}

@available(iOS 14.0, macOS 11.0, *)
private struct MarkdownRenderConfiguration {
    let parseKey: MarkdownParseKey
    let theme: Theme
    let plugins: [ASTPlugin]
    let width: CGFloat
    let diagramRegistry: DiagramAdapterRegistry
    let imageLoadingPolicy: ImageLoadingPolicy
    let appearance: MarkdownAppearance

    var markdown: String { parseKey.text }
    var resourceLimits: MarkdownParser.ResourceLimits { parseKey.resourceLimits }

    func withWidth(_ width: CGFloat) -> MarkdownRenderConfiguration {
        MarkdownRenderConfiguration(
            parseKey: parseKey,
            theme: theme,
            plugins: plugins,
            width: width,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy,
            appearance: appearance
        )
    }
}

@available(iOS 14.0, macOS 11.0, *)
private struct RenderRequest {
    let generation: UInt64
    let configuration: MarkdownRenderConfiguration
}

@available(iOS 14.0, macOS 11.0, *)
private struct CachedRawAST {
    let parseKey: MarkdownParseKey
    let document: DocumentNode
}

@available(iOS 14.0, macOS 11.0, *)
private enum RawASTPreparation {
    case parse
    case reuse(DocumentNode)
}

@available(iOS 14.0, macOS 11.0, *)
private struct RenderWork: @unchecked Sendable {
    let generation: UInt64
    let parseKey: MarkdownParseKey
    let markdown: String
    let plugins: [ASTPlugin]
    let resourceLimits: MarkdownParser.ResourceLimits
    let rawASTPreparation: RawASTPreparation
    let solver: LayoutSolver
    let width: CGFloat
    let disclosureOverrides: [DetailsOverrideKey: Bool]
}

@available(iOS 14.0, macOS 11.0, *)
private struct RenderOutput: @unchecked Sendable {
    let generation: UInt64
    let parseKey: MarkdownParseKey
    let rawAST: DocumentNode
    let childLayouts: [LayoutResult]?
}

@available(iOS 14.0, macOS 11.0, *)
private struct DetailsOverrideKey: Hashable, Sendable {
    let index: Int
    let summaryFingerprint: Int?
    let childFingerprints: [Int]

    init(index: Int, details: DetailsNode) {
        self.index = index
        self.summaryFingerprint = details.summary?.contentFingerprint
        self.childFingerprints = details.children.map(\.contentFingerprint)
    }
}
#endif
