//
//  LayoutCache.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A thread-safe cache storing previously computed layout results.
/// Because AST sizing is inherently tied to the bounding container width (e.g. device rotation),
/// the cache is keyed using a combination of the Node's unique ID and the constrained width.
public final class LayoutCache {
    
    /// The internal key structure for NSCache.
    private class CacheKey: NSObject {
        let nodeId: UUID
        let normalizedWidthBucket: Int
        private static let widthBucketScale: CGFloat = 10.0 // 0.1pt buckets
        
        init(nodeId: UUID, width: CGFloat) {
            self.nodeId = nodeId
            self.normalizedWidthBucket = CacheKey.widthBucket(for: width)
        }
        
        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(nodeId)
            hasher.combine(normalizedWidthBucket)
            return hasher.finalize()
        }
        
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else { return false }
            return self.nodeId == other.nodeId
                && self.normalizedWidthBucket == other.normalizedWidthBucket
        }

        private static func widthBucket(for width: CGFloat) -> Int {
            guard width.isFinite else { return 0 }
            return Int((width * widthBucketScale).rounded(.towardZero))
        }
    }
    
    private let cache = NSCache<CacheKey, LayoutResultWrapper>()
    
    // NSCache requires class objects, so we wrap the struct LayoutResult
    private class LayoutResultWrapper {
        let result: LayoutResult
        init(_ result: LayoutResult) {
            self.result = result
        }
    }
    
    public init(countLimit: Int = 100_000) {
        // Limit cache to prevent memory pressure on massive documents.
        // 100k layout models usually take single-digit megabytes since they are purely structs of CGRects.
        cache.countLimit = countLimit
    }
    
    /// Retrieve a pre-calculated layout if it exists for the given node and container width.
    public func getLayout(for node: MarkdownNode, constrainedToWidth width: CGFloat) -> LayoutResult? {
        let key = CacheKey(nodeId: node.id, width: width)
        return cache.object(forKey: key)?.result
    }
    
    /// Store a freshly computed layout frame.
    public func setLayout(_ result: LayoutResult, constrainedToWidth width: CGFloat) {
        let key = CacheKey(nodeId: result.node.id, width: width)
        let wrapper = LayoutResultWrapper(result)
        cache.setObject(wrapper, forKey: key)
    }
    
    /// Clears all stored layouts (e.g. upon memory warning).
    public func clear() {
        cache.removeAllObjects()
    }
}
