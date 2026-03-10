#if canImport(SwiftUI)
import SwiftUI

#if canImport(UIKit)
import UIKit

@available(iOS 14.0, *)
struct MarkdownViewRepresentable: UIViewRepresentable {
    let layouts: [LayoutResult]
    let onToggleDetails: (Int, DetailsNode) -> Void
    var onLinkTap: ((URL) -> Void)?
    var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?
    var theme: Theme = .default

    func makeUIView(context: Context) -> MarkdownCollectionView {
        let view = MarkdownCollectionView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: MarkdownCollectionView, context: Context) {
        uiView.theme = theme
        uiView.layouts = layouts
        uiView.onToggleDetails = onToggleDetails
        uiView.onLinkTap = onLinkTap
        uiView.onCheckboxToggle = onCheckboxToggle
    }
}

#elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

@available(macOS 11.0, *)
struct MarkdownViewRepresentable: NSViewRepresentable {
    let layouts: [LayoutResult]
    let onToggleDetails: (Int, DetailsNode) -> Void
    var onLinkTap: ((URL) -> Void)?
    var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?
    var theme: Theme = .default

    func makeNSView(context: Context) -> MarkdownCollectionView {
        let view = MarkdownCollectionView()
        return view
    }

    func updateNSView(_ nsView: MarkdownCollectionView, context: Context) {
        nsView.theme = theme
        nsView.layouts = layouts
        nsView.onToggleDetails = onToggleDetails
        nsView.onLinkTap = onLinkTap
        nsView.onToggleCheckbox = onCheckboxToggle
    }
}
#endif
#endif
