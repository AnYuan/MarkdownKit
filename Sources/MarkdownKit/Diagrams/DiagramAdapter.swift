import Foundation

public protocol DiagramRenderingAdapter: Sendable {
    func render(source: String, language: DiagramLanguage) async -> NSAttributedString?
    func cacheFingerprint(into hasher: inout Hasher)
}

public extension DiagramRenderingAdapter {
    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: type(of: self)))
    }
}

/// Registry for host-provided diagram rendering adapters.
///
/// If no adapter exists for a language, renderers should fall back to code-block output.
public struct DiagramAdapterRegistry: Sendable {
    private var adapters: [DiagramLanguage: any DiagramRenderingAdapter]

    public init(adapters: [DiagramLanguage: any DiagramRenderingAdapter] = [:]) {
        self.adapters = adapters
    }

    public mutating func register(_ adapter: any DiagramRenderingAdapter, for language: DiagramLanguage) {
        adapters[language] = adapter
    }

    public func adapter(for language: DiagramLanguage) -> (any DiagramRenderingAdapter)? {
        adapters[language]
    }

    var cacheFingerprint: Int {
        var hasher = Hasher()
        for language in DiagramLanguage.allCases {
            guard let adapter = adapters[language] else { continue }
            hasher.combine(language.rawValue)
            adapter.cacheFingerprint(into: &hasher)
        }
        return hasher.finalize()
    }
}
