//
//  DemoApp.swift
//  MyMarkdownDemo
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import SwiftUI
import AppKit
import MyMarkdown

@main
struct DemoApp: App {
    init() {
        // SPM executables are bare binaries without .app bundle,
        // so macOS won't show windows unless we explicitly register as a regular app.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            DemoContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
    }
}

struct DemoContentView: View {
    @State private var markdown = DemoContent.giantDocument
    @State private var renderTime: Double = 0
    @State private var isRendering: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MyMarkdown Virtualized Rendering Demo")
                    .font(.headline)
                Spacer()
                if isRendering {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Text(String(format: "Asynchronous Layout Completed In: %.2f ms", renderTime))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            GeometryReader { geo in
                MarkdownViewRep(markdown: markdown, width: geo.size.width, renderTime: $renderTime, isRendering: $isRendering)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }
}

struct MarkdownViewRep: NSViewRepresentable {
    let markdown: String
    let width: CGFloat
    
    @Binding var renderTime: Double
    @Binding var isRendering: Bool
    
    func makeNSView(context: Context) -> MarkdownCollectionView {
        let view = MarkdownCollectionView()
        return view
    }
    
    func updateNSView(_ nsView: MarkdownCollectionView, context: Context) {
        // Prevent layout storm on tiny width loading
        guard width > 100 else { return }
        
        // Very basic deduplication for the demo environment so we don't recalculate on every minor frame update
        if context.coordinator.lastWidth != width {
            context.coordinator.lastWidth = width
            
            Task {
                await MainActor.run { isRendering = true }
                
                let start = CFAbsoluteTimeGetCurrent()
                
                let parser = MarkdownParser()
                let ast = parser.parse(markdown) // Fast 1-thread Parse
                
                // Background Layout Pass (Where the Magic Happens)
                let solver = LayoutSolver()
                let result = await solver.solve(node: ast, constrainedToWidth: width)
                
                let end = CFAbsoluteTimeGetCurrent()
                
                await MainActor.run {
                    self.renderTime = (end - start) * 1000
                    self.isRendering = false
                    nsView.layouts = result.children
                    nsView.frame.size = CGSize(width: width, height: nsView.frame.height)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var lastWidth: CGFloat = 0
    }
}

struct DemoContent {
    static let chunk = """
    # Virtualized Node Memory Stress Test
    
    This acts as a brutal stress test for the `MyMarkdown` asynchronous rendering pipeline and cache. The goal is to aggressively verify that memory stays completely flat, even when the user is scrolling rapidly through thousands of natively-rendered view nodes.
    
    ## Phase 1 & 2: Abstract Syntax Tree & Background Layout
    Every node you see here was instantly passed into Apple's `swift-markdown` library for C-level AST processing, mapped into our thread-safe format, and pushed to a Background Global Queue.
    
    ```swift
    // This exact snippet block is heavily parsed by John Sundell's `Splash` engine natively in the background.
    public final class LayoutSolver {
        public func solve(node: MarkdownNode, width: CGFloat) async -> LayoutResult {
            // Expensive TextKit 2 measurement math executes freely without blocking the UI thread.
            return LayoutResult(node: node)
        }
    }
    ```
    
    ## Phase 3: TextureKit Virtualization
    Here is an inline math equation $O(N)$ and a block equation to test our invisible WebKit background rendering queue:
    
    $$
    E = mc^2 \\approx \\text{Mass-Energy Equivalence}
    $$
    
    As you scroll, `AsyncImageView`, `AsyncTextView`, and `AsyncCodeView` monitor `display(in:)` cycles natively triggering internal cache drops and `.contents` purges when pushed off-screen.
    
    ### Phase 4 Feature Verification Task List
    - [x] Splash Swift Highlighting Integration
    - [x] MathJax WebKit Actor Encapsulation
    - [x] Copy/Paste UX Overlays
    - [x] Grid Layout Tables
    
    | Library Engine | Native Swift | Virtualized OS-Memory | Async UI Layout |
    |---|---|---|---|
    | Highlight.js WebViews | False | False | False |
    | Texture (AsyncDisplayKit) | Objective-C | True | True |
    | **MyMarkdown** | **True** | **True** | **True** |
    
    ![Unsplash Demo Image 1](https://images.unsplash.com/photo-1542831371-29b0f74f9713?w=800&q=80)
    """
    
    static var giantDocument: String {
        return String(repeating: chunk + "\n\n---\n\n", count: 100)
    }
}
#endif
