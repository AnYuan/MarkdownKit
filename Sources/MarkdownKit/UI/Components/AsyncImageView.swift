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

    /// Shared cache of decoded, downsampled images keyed by `(url, target size,
    /// scale)`. Distinct from `ImageAttachmentBuilder.cache`, which holds the
    /// raw `UIImage` used by inline text attachments. Block-display images
    /// (rendered via this view) are decoded at the block's target size and
    /// can't be reused at the inline size.
    /// `countLimit` is a soft cap.
    nonisolated(unsafe) private static let imageCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 64
        return c
    }()

    /// Drops all decoded block-display images. Hosts can call this from
    /// memory-warning handlers.
    public static func clearImageCache() {
        imageCache.removeAllObjects()
    }

    private static func cacheKey(url: URL, size: CGSize, scale: CGFloat) -> String {
        "\(url.absoluteString)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))@\(scale)"
    }

    /// When `true` (the default), images are fetched and decoded on a background queue.
    /// Set to `false` to load file-URL images synchronously on the main thread (useful for
    /// snapshot testing). Network URLs still use async loading regardless of this flag.
    public var displaysAsynchronously: Bool = true

    public var imageLoadingPolicy: ImageLoadingPolicy = .default

    private var currentImageTask: Task<Void, Never>?
    private let urlSession: URLSession

    /// Cached display scale, refreshed in `didMoveToWindow` so external
    /// displays / iPad split-view get the correct value. Replaces the
    /// deprecated `UIScreen.main.scale`.
    private var currentDisplayScale: CGFloat = 1

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
        self.currentDisplayScale = resolveDisplayScale()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        currentDisplayScale = resolveDisplayScale()
    }

    private func resolveDisplayScale() -> CGFloat {
        if let scale = window?.windowScene?.screen.scale, scale > 0 {
            return scale
        }
        let trait = traitCollection.displayScale
        return trait > 0 ? trait : 2
    }
    
    /// Resets internal state so the view can be reused by a recycling cell.
    public func prepareForReuse() {
        currentImageTask?.cancel()
        currentImageTask = nil
        layer.contents = nil
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

        // Fast path: another cell already decoded this URL at this exact size.
        // Mounts synchronously, avoids re-download and re-decode on scroll-back.
        let cacheKey = Self.cacheKey(url: resolved.url, size: targetSize, scale: currentDisplayScale)
        if let cached = Self.imageCache.object(forKey: cacheKey as NSString) {
            layer.contents = cached.cgImage
            return
        }

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
            let scale = currentDisplayScale
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let decoded = renderer.image { _ in
                sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            Self.imageCache.setObject(decoded, forKey: cacheKey as NSString)
            self.layer.contents = decoded.cgImage
            return
        }

        // Capture the display scale on the main actor before we drop off it,
        // so the background decoder doesn't have to hop back to MainActor
        // just to read `UIScreen.main`.
        let resolvedScale = currentDisplayScale

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
            let format = UIGraphicsImageRendererFormat()
            format.scale = resolvedScale
            
            // Calculate a resizing constraint that preserves aspect ratio but shrinks the huge photo
            // into the small bounding box LayoutSolver determined.
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let decodedImage = renderer.image { _ in
                sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            
            if Task.isCancelled { return }

            // Populate the shared cache before the main-actor hop. NSCache is
            // documented as thread-safe, so this is safe off-main.
            Self.imageCache.setObject(decodedImage, forKey: cacheKey as NSString)

            // 5. Mount the uncompressed GPU-ready buffer to the layer (Instantaneous)
            await MainActor.run {
                self.layer.contents = decodedImage.cgImage
            }
        }
    }
}
#endif
