#if canImport(SwiftUI)
import SwiftUI

#if canImport(UIKit)
import UIKit

@available(iOS 14.0, *)
struct MarkdownViewRepresentable: UIViewRepresentable {
    let layouts: [LayoutResult]
    let onToggleDetails: (Int, DetailsNode) -> Void
    var onEffectiveContentWidthChange: ((CGFloat) -> Void)? = nil
    var onLinkTap: ((URL) -> Void)?
    var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?
    var theme: Theme = .default
    var textInteractionMode: MarkdownTextInteractionMode = .asyncReadOnly

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
        uiView.textInteractionMode = textInteractionMode
    }
}

#elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

@available(macOS 11.0, *)
struct MarkdownViewRepresentable: NSViewRepresentable {
    let layouts: [LayoutResult]
    let onToggleDetails: (Int, DetailsNode) -> Void
    var onEffectiveContentWidthChange: ((CGFloat) -> Void)?
    var onLinkTap: ((URL) -> Void)?
    var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?
    var theme: Theme = .default
    var textInteractionMode: MarkdownTextInteractionMode = .asyncReadOnly

    func makeNSView(context: Context) -> MarkdownCollectionView {
        let view = MarkdownCollectionView()
        view.onEffectiveContentWidthChange = onEffectiveContentWidthChange
        return view
    }

    func updateNSView(_ nsView: MarkdownCollectionView, context: Context) {
        nsView.theme = theme
        nsView.layouts = layouts
        nsView.onToggleDetails = onToggleDetails
        nsView.onEffectiveContentWidthChange = onEffectiveContentWidthChange
        nsView.onLinkTap = onLinkTap
        nsView.onToggleCheckbox = onCheckboxToggle
        nsView.textInteractionMode = textInteractionMode
    }
}
#endif
#endif
