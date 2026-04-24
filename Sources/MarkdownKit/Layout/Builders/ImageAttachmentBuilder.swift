//
//  ImageAttachmentBuilder.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A dedicated builder for converting `ImageNode` entities into fully scaled
/// and measured `NSTextAttachment` strings for layout inline embedding.
struct ImageAttachmentBuilder {
    
    // An NSCache instance for thread-safe cross-layout image reuse
    nonisolated(unsafe) private static let cache = NSCache<NSString, NativeImage>()

    static func build(
        from imageNode: ImageNode,
        constrainedToWidth maxWidth: CGFloat,
        imageLoadingPolicy: ImageLoadingPolicy = .default
    ) async -> NSAttributedString? {
        guard let source = imageNode.source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            return nil
        }
        
        // Fast path: cached image
        let cacheKey = NSString(string: "\(imageLoadingPolicy.cacheFingerprint):\(source)")
        let nativeImage: NativeImage
        
        if let cached = cache.object(forKey: cacheKey) {
            nativeImage = cached
        } else {
            // Respect cooperative cancellation during slow downloads
            try? Task.checkCancellation()
            
            guard let downloaded = await loadImage(from: source, policy: imageLoadingPolicy) else { return nil }
            nativeImage = downloaded
            cache.setObject(downloaded, forKey: cacheKey)
        }

        let imageSize = nativeImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let maxAttachmentWidth = max(80, maxWidth - 24)
        let scale = min(1.0, maxAttachmentWidth / imageSize.width)
        let targetSize = CGSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )

        let attachment = NSTextAttachment()
        #if canImport(UIKit)
        attachment.image = nativeImage
        #elseif canImport(AppKit)
        attachment.image = nativeImage
        #endif
        attachment.bounds = CGRect(origin: .zero, size: targetSize)
        return NSAttributedString(attachment: attachment)
    }

    private static func loadImage(from source: String, policy: ImageLoadingPolicy) async -> NativeImage? {
        guard let resolved = ImageSourceResolver.resolve(source),
              policy.allows(resolved) else { return nil }

        do {
            let data: Data
            if resolved.url.isFileURL {
                if let fileSize = try? resolved.url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   !policy.allowsDataCount(fileSize) {
                    return nil
                }
                data = try Data(contentsOf: resolved.url)
            } else {
                let request = URLRequest(
                    url: resolved.url,
                    cachePolicy: .returnCacheDataElseLoad,
                    timeoutInterval: 12.0
                )
                let (networkData, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    return nil
                }
                if response.expectedContentLength >= 0,
                   !policy.allowsByteCount(response.expectedContentLength) {
                    return nil
                }
                if let mimeType = response.mimeType?.lowercased(),
                   !mimeType.hasPrefix("image/") {
                    return nil
                }
                data = networkData
            }

            guard !data.isEmpty, policy.allowsDataCount(data.count) else { return nil }
            return NativeImage(data: data)
        } catch {
            return nil
        }
    }
}
