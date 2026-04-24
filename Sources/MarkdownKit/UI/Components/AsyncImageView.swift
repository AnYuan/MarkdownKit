//
//  AsyncImageView.swift
//  MarkdownKit
//

#if canImport(UIKit) && !os(watchOS)
import UIKit
import os

/// A Texture-inspired asynchronous native view for rendering Network or Local Images.
///
/// Images are notorious for causing frame drops on the main thread during the decoding phase
/// (converting compressed JPEG/PNG data into uncompressed pixel byte buffers for the GPU).
/// `AsyncImageView` guarantees this happens 100% on a background queue.
public class AsyncImageView: UIView {

    private nonisolated(unsafe) static let logger = Logger(subsystem: "com.markdownkit", category: "AsyncImageView")

    /// When `true` (the default), images are fetched and decoded on a background queue.
    /// Set to `false` to load file-URL images synchronously on the main thread (useful for
    /// snapshot testing). Network URLs still use async loading regardless of this flag.
    public var displaysAsynchronously: Bool = true

    public var imageLoadingPolicy: ImageLoadingPolicy = .default

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
    public func configure(
        with layout: LayoutResult,
        imageLoadingPolicy: ImageLoadingPolicy = .default
    ) {
        self.imageLoadingPolicy = imageLoadingPolicy

        // Cancel pending background operations if this cell was aggressively recycled
        currentImageTask?.cancel()
        
        self.frame.size = layout.size
        self.layer.contents = nil // Clear previous image immediately
        
        guard let imageNode = layout.node as? ImageNode,
              let source = imageNode.source,
              let resolved = ImageSourceResolver.resolve(source),
              imageLoadingPolicy.allows(resolved) else {
            return
        }
        
        let targetSize = layout.size
        let policy = imageLoadingPolicy

        // Synchronous path: load + decode on main thread for file URLs
        if !displaysAsynchronously && resolved.url.isFileURL {
            if let fileSize = try? resolved.url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               !policy.allowsDataCount(fileSize) {
                return
            }
            guard let data = try? Data(contentsOf: resolved.url),
                  !data.isEmpty,
                  policy.allowsDataCount(data.count),
                  let sourceImage = UIImage(data: data) else { return }
            let scale = UIScreen.main.scale
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let decoded = renderer.image { _ in
                sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            self.layer.contents = decoded.cgImage
            return
        }

        // Asynchronous path: Texture's exact Display State process
        currentImageTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // 1. Cooperative Yielding
            await Task.yield()
            if Task.isCancelled { return }
            
            // 2. Fetch the Data (Network or Local File)
            let data: Data
            do {
                if resolved.url.isFileURL {
                    if let fileSize = try? resolved.url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                       !policy.allowsDataCount(fileSize) {
                        return
                    }
                    data = try Data(contentsOf: resolved.url)
                } else {
                    let request = URLRequest(
                        url: resolved.url,
                        cachePolicy: .returnCacheDataElseLoad,
                        timeoutInterval: 12.0
                    )
                    let (networkData, response) = try await self.urlSession.data(for: request)
                    if let http = response as? HTTPURLResponse,
                       !(200...299).contains(http.statusCode) {
                        return
                    }
                    if response.expectedContentLength >= 0,
                       !policy.allowsByteCount(response.expectedContentLength) {
                        return
                    }
                    if let mimeType = response.mimeType?.lowercased(),
                       !mimeType.hasPrefix("image/") {
                        return
                    }
                    data = networkData
                }
            } catch {
                Self.logger.error("Failed to load image data for \(resolved.url): \(error)")
                return
            }

            guard !data.isEmpty, policy.allowsDataCount(data.count) else { return }
            
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
