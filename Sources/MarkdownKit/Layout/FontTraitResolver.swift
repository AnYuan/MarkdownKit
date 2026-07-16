//
//  FontTraitResolver.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum FontTraitResolver {
    enum Trait: Hashable {
        case bold
        case italic
    }

    private struct CacheKey: Hashable {
        let familyName: String?
        let fontName: String
        let pointSizeBits: UInt64
        let existingTraits: UInt
        let addedTrait: Trait
    }

    private final class DerivedFontCache: @unchecked Sendable {
        struct Stats {
            let hits: Int
            let misses: Int
        }

        private let capacity: Int
        private let lock = NSLock()
        private var fonts: [CacheKey: Font] = [:]
        private var insertionOrder: [CacheKey] = []
        private var hits = 0
        private var misses = 0

        init(capacity: Int) {
            self.capacity = capacity
        }

        func font(for key: CacheKey, derive: () -> Font) -> Font {
            lock.lock()
            if let cachedFont = fonts[key] {
                hits += 1
                lock.unlock()
                return cachedFont
            }
            lock.unlock()

            let derivedFont = derive()

            lock.lock()
            defer { lock.unlock() }
            if let cachedFont = fonts[key] {
                hits += 1
                return cachedFont
            }

            misses += 1
            if fonts.count >= capacity, let oldestKey = insertionOrder.first {
                fonts.removeValue(forKey: oldestKey)
                insertionOrder.removeFirst()
            }
            fonts[key] = derivedFont
            insertionOrder.append(key)
            return derivedFont
        }

        func stats() -> Stats {
            lock.lock()
            defer { lock.unlock() }
            return Stats(hits: hits, misses: misses)
        }

        func reset() {
            lock.lock()
            fonts.removeAll(keepingCapacity: true)
            insertionOrder.removeAll(keepingCapacity: true)
            hits = 0
            misses = 0
            lock.unlock()
        }
    }

    private static let cache = DerivedFontCache(capacity: 256)

    static func adding(_ trait: Trait, to font: Font) -> Font {
        #if canImport(UIKit)
        let descriptor = font.fontDescriptor
        var traits = descriptor.symbolicTraits
        let existingTraits = traits
        switch trait {
        case .bold:
            traits.insert(.traitBold)
        case .italic:
            traits.insert(.traitItalic)
        }

        let key = cacheKey(for: font, existingTraits: UInt(existingTraits.rawValue), addedTrait: trait)
        return cache.font(for: key) {
            guard let derivedDescriptor = descriptor.withSymbolicTraits(traits) else {
                return font
            }

            let derivedFont = Font(descriptor: derivedDescriptor, size: font.pointSize)
            guard derivedFont.familyName == font.familyName,
                  derivedFont.fontDescriptor.symbolicTraits.intersection(traits) == traits else {
                return font
            }
            return derivedFont
        }
        #elseif canImport(AppKit)
        var traits = NSFontTraitMask(
            rawValue: UInt(
                font.fontDescriptor.symbolicTraits
                    .subtracting(.classMask)
                    .rawValue
            )
        )
        let existingTraits = traits
        switch trait {
        case .bold:
            traits.remove(.unboldFontMask)
            traits.insert(.boldFontMask)
        case .italic:
            traits.remove(.unitalicFontMask)
            traits.insert(.italicFontMask)
        }

        let key = cacheKey(for: font, existingTraits: existingTraits.rawValue, addedTrait: trait)
        return cache.font(for: key) {
            let manager = NSFontManager.shared
            var derivedFont = manager.convert(font, toHaveTrait: traits)
            if derivedFont.pointSize != font.pointSize {
                derivedFont = manager.convert(derivedFont, toSize: font.pointSize)
            }
            derivedFont = managerAdvertisedFamilyMember(
                matching: traits,
                guidedBy: derivedFont,
                manager: manager
            ) ?? derivedFont

            guard derivedFont.familyName == font.familyName,
                  manager.traits(of: derivedFont).intersection(traits) == traits else {
                return font
            }
            return derivedFont
        }
        #endif
    }

    static func cacheStatsForTesting() -> (hits: Int, misses: Int) {
        let stats = cache.stats()
        return (stats.hits, stats.misses)
    }

    static func resetCacheForTesting() {
        cache.reset()
    }

    private static func cacheKey(
        for font: Font,
        existingTraits: UInt,
        addedTrait: Trait
    ) -> CacheKey {
        CacheKey(
            familyName: font.familyName,
            fontName: font.fontName,
            pointSizeBits: Double(font.pointSize).bitPattern,
            existingTraits: existingTraits,
            addedTrait: addedTrait
        )
    }

    #if canImport(AppKit) && !canImport(UIKit)
    private static func managerAdvertisedFamilyMember(
        matching requestedTraits: NSFontTraitMask,
        guidedBy convertedFont: Font,
        manager: NSFontManager
    ) -> Font? {
        guard let familyName = convertedFont.familyName,
              let members = manager.availableMembers(ofFontFamily: familyName) else {
            return nil
        }

        let targetWeight = manager.weight(of: convertedFont)
        var bestMatch: (distance: Int, font: Font)?

        for member in members {
            guard member.count >= 4,
                  let fontName = member[0] as? String,
                  let weight = member[2] as? Int,
                  let rawTraits = member[3] as? UInt,
                  NSFontTraitMask(rawValue: rawTraits) == requestedTraits,
                  let candidate = Font(name: fontName, size: convertedFont.pointSize),
                  candidate.familyName == familyName else {
                continue
            }

            let distance = abs(weight - targetWeight)
            if let currentBest = bestMatch, currentBest.distance <= distance {
                continue
            } else {
                bestMatch = (distance, candidate)
            }
        }
        return bestMatch?.font
    }
    #endif
}
