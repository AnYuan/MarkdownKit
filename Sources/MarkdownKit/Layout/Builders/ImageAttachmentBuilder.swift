//
//  ImageAttachmentBuilder.swift
//  MarkdownKit
//

import Foundation
import ImageIO
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A dedicated builder for converting `ImageNode` entities into fully scaled
/// and measured `NSTextAttachment` strings for layout inline embedding.
struct ImageAttachmentBuilder {
    private static let maximumDecodedByteCost = 64 * 1024 * 1024
    private static let logger = Logger(
        subsystem: "com.markdownkit",
        category: "ImageAttachmentBuilder"
    )

    private final class CachedImage: NSObject {
        let image: NativeImage
        let attachmentSize: CGSize
        let decodedByteCost: Int

        init(image: NativeImage, attachmentSize: CGSize, decodedByteCost: Int) {
            self.image = image
            self.attachmentSize = attachmentSize
            self.decodedByteCost = decodedByteCost
        }
    }

    // Cache decoded, already-downsampled images rather than compressed source
    // data. The key includes the requested width so a narrow thumbnail cannot
    // be reused at a wider inline layout.
    nonisolated(unsafe) private static let cache: NSCache<NSString, CachedImage> = {
        let cache = NSCache<NSString, CachedImage>()
        cache.countLimit = 128
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// Drops all cached attachment images. Hosts can call this from memory
    /// warnings or when switching image-loading policies.
    public static func clearCache() {
        cache.removeAllObjects()
    }

    static func build(
        from imageNode: ImageNode,
        constrainedToWidth maxWidth: CGFloat,
        imageLoadingPolicy: ImageLoadingPolicy = .default,
        imageResourceLoader: ImageResourceLoader = .shared
    ) async -> NSAttributedString? {
        guard !Task.isCancelled,
              let source = imageNode.source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            return nil
        }

        let maxAttachmentWidth = max(80, maxWidth - 24)
        guard maxAttachmentWidth.isFinite, maxAttachmentWidth > 0 else {
            return nil
        }

        let cacheKey = cacheKey(
            source: source,
            policy: imageLoadingPolicy,
            targetWidth: maxAttachmentWidth
        )
        if let cached = cache.object(forKey: cacheKey) {
            guard !Task.isCancelled else { return nil }
            return attachmentString(from: cached)
        }

        guard !Task.isCancelled else { return nil }
        let resource: LoadedImageResource
        do {
            resource = try await imageResourceLoader.load(
                source: source,
                policy: imageLoadingPolicy
            )
        } catch {
            guard !Task.isCancelled else { return nil }
            logger.debug("Image load rejected: \(String(describing: error), privacy: .private)")
            return nil
        }
        guard !Task.isCancelled else { return nil }
        guard let decoded = decode(resource.data, maxAttachmentWidth: maxAttachmentWidth) else {
            logger.debug("Image data could not be decoded within the configured bounds")
            return nil
        }

        // NSCache is thread-safe. Do not publish results from a cancelled
        // layout task, which could otherwise keep unnecessary decoded pixels.
        guard !Task.isCancelled else { return nil }
        cache.setObject(decoded, forKey: cacheKey, cost: decoded.decodedByteCost)
        return attachmentString(from: decoded)
    }

    private static func cacheKey(
        source: String,
        policy: ImageLoadingPolicy,
        targetWidth: CGFloat
    ) -> NSString {
        let roundedTargetWidth = Int(targetWidth.rounded(.toNearestOrAwayFromZero))
        return "\(policy.cacheFingerprint)|\(roundedTargetWidth)|\(source)" as NSString
    }

    private static func decode(
        _ data: Data,
        maxAttachmentWidth: CGFloat
    ) -> CachedImage? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              pixelWidth > 0,
              pixelHeight > 0 else {
            return nil
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let orientedSourceSize: CGSize
        switch orientation {
        case 5, 6, 7, 8:
            orientedSourceSize = CGSize(width: pixelHeight, height: pixelWidth)
        default:
            orientedSourceSize = CGSize(width: pixelWidth, height: pixelHeight)
        }

        let scale = min(1, maxAttachmentWidth / orientedSourceSize.width)
        let attachmentSize = CGSize(
            width: max(1, orientedSourceSize.width * scale),
            height: max(1, orientedSourceSize.height * scale)
        )
        let estimatedDecodedByteCost = attachmentSize.width * attachmentSize.height * 4
        guard attachmentSize.width.isFinite,
              attachmentSize.height.isFinite,
              estimatedDecodedByteCost.isFinite,
              estimatedDecodedByteCost <= CGFloat(maximumDecodedByteCost) else {
            return nil
        }

        let maxPixelDimensionValue = ceil(max(attachmentSize.width, attachmentSize.height))
        guard maxPixelDimensionValue <= CGFloat(Int.max) else { return nil }
        let maxPixelDimension = max(1, Int(maxPixelDimensionValue))
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return nil
        }

        #if canImport(UIKit)
        let image = NativeImage(cgImage: cgImage, scale: 1, orientation: .up)
        #elseif canImport(AppKit)
        let image = NativeImage(cgImage: cgImage, size: attachmentSize)
        #endif
        guard let decodedByteCost = decodedByteCost(of: cgImage),
              decodedByteCost <= maximumDecodedByteCost else {
            return nil
        }
        return CachedImage(
            image: image,
            attachmentSize: attachmentSize,
            decodedByteCost: decodedByteCost
        )
    }

    private static func decodedByteCost(of image: CGImage) -> Int? {
        let (byteCost, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        return overflow ? nil : byteCost
    }

    private static func attachmentString(from cached: CachedImage) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = cached.image
        attachment.bounds = CGRect(origin: .zero, size: cached.attachmentSize)
        return NSAttributedString(attachment: attachment)
    }
}
