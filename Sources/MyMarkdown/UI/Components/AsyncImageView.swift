//
//  AsyncImageView.swift
//  MyMarkdown
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// A Texture-inspired asynchronous native view for rendering Network or Local Images.
///
/// Images are notorious for causing frame drops on the main thread during the decoding phase
/// (converting compressed JPEG/PNG data into uncompressed pixel byte buffers for the GPU).
/// `AsyncImageView` guarantees this happens 100% on a background queue.
public class AsyncImageView: UIView {
    
    private var currentImageTask: Task<Void, Never>?
    private let urlSession: URLSession
    
    public override init(frame: CGRect) {
        // High-level shared session for prototype
        self.urlSession = URLSession.shared 
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        self.urlSession = URLSession.shared
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        self.backgroundColor = .clear
        
        // Essential: CoreAnimation will automatically scale our CGImage bytes into the bounding box
        self.layer.contentsGravity = .resizeAspect
    }
    
    /// Binds the `LayoutResult` constraint to the view, launching an asynchronous download and decoding operation.
    public func configure(with layout: LayoutResult) {
        // Cancel pending background operations if this cell was aggressively recycled
        currentImageTask?.cancel()
        
        self.frame.size = layout.size
        self.layer.contents = nil // Clear previous image immediately
        
        guard let imageNode = layout.node as? ImageNode,
              let urlString = imageNode.source,
              let url = URL(string: urlString) else {
            return
        }
        
        let targetSize = layout.size
        
        // Start Texture's exact Display State process
        currentImageTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // 1. Cooperative Yielding
            await Task.yield()
            if Task.isCancelled { return }
            
            // 2. Fetch the Data (Network or Local File)
            let data: Data
            do {
                if url.isFileURL {
                    data = try Data(contentsOf: url)
                } else {
                    let (networkData, _) = try await self.urlSession.data(from: url)
                    data = networkData
                }
            } catch {
                print("Failed to load image data for \(url): \(error)")
                return
            }
            
            if Task.isCancelled { return }
            
            // 3. Texture Core Concept: Background Decoding
            // Instantiating a UIImage does NOT decode it. It just points to compressed data.
            // Drawing it into a fresh CGContext forces the CPU to inflate the JPEG/PNG bytes 
            // into an uncompressed pixel matrix before it reaches the main UI thread.
            guard let sourceImage = UIImage(data: data) else { return }
            
            // 4. Background Downsampling (Memory Optimization)
            let scale = await UIScreen.main.scale
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            
            // Calculate a resizing constraint that preserves aspect ratio but shrinks the huge photo
            // into the small bounding box LayoutSolver determined.
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let decodedImage = renderer.image { _ in
                sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            
            if Task.isCancelled { return }
            
            // 5. Mount the uncompressed GPU-ready buffer to the layer (Instantaneous)
            await MainActor.run {
                self.layer.contents = decodedImage.cgImage
            }
        }
    }
}
#endif
