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

    struct CacheKey: Hashable {
        private let familyName: String?
        private let fontName: String
        private let pointSizeBits: UInt64
        private let existingTraits: UInt
        private let addedTrait: Trait

        init(
            familyName: String?,
            fontName: String,
            pointSizeBits: UInt64,
            existingTraits: UInt,
            addedTrait: Trait
        ) {
            self.familyName = familyName
            self.fontName = fontName
            self.pointSizeBits = pointSizeBits
            self.existingTraits = existingTraits
            self.addedTrait = addedTrait
        }
    }

    /// `@unchecked Sendable`: `lock` guards cache, LRU-list, and statistics state.
    final class DerivedFontCache: @unchecked Sendable {
        struct Stats {
            let hits: Int
            let misses: Int
        }

        private final class Entry {
            let key: CacheKey
            let font: Font
            weak var previous: Entry?
            var next: Entry?

            init(key: CacheKey, font: Font) {
                self.key = key
                self.font = font
            }
        }

        private let capacity: Int
        private let lock = NSLock()
        private var entries: [CacheKey: Entry] = [:]
        private var mostRecentEntry: Entry?
        private var leastRecentEntry: Entry?
        private var hits = 0
        private var misses = 0

        init(capacity: Int) {
            self.capacity = max(0, capacity)
            if self.capacity > 0 {
                entries.reserveCapacity(self.capacity)
            }
        }

        func font(for key: CacheKey, derive: () -> Font) -> Font {
            lock.lock()
            if let entry = entries[key] {
                hits += 1
                moveToMostRecent(entry)
                lock.unlock()
                return entry.font
            }
            lock.unlock()

            let derivedFont = derive()

            lock.lock()
            defer { lock.unlock() }
            if let entry = entries[key] {
                hits += 1
                moveToMostRecent(entry)
                return entry.font
            }

            misses += 1
            guard capacity > 0 else { return derivedFont }
            if entries.count >= capacity, let entry = leastRecentEntry {
                remove(entry)
            }
            let entry = Entry(key: key, font: derivedFont)
            entries[key] = entry
            attachAsMostRecent(entry)
            return derivedFont
        }

        func stats() -> Stats {
            lock.lock()
            defer { lock.unlock() }
            return Stats(hits: hits, misses: misses)
        }

        func reset() {
            lock.lock()
            entries.removeAll(keepingCapacity: true)
            mostRecentEntry = nil
            leastRecentEntry = nil
            hits = 0
            misses = 0
            lock.unlock()
        }

        private func moveToMostRecent(_ entry: Entry) {
            guard mostRecentEntry !== entry else { return }
            detach(entry)
            attachAsMostRecent(entry)
        }

        private func attachAsMostRecent(_ entry: Entry) {
            entry.previous = nil
            entry.next = mostRecentEntry
            mostRecentEntry?.previous = entry
            mostRecentEntry = entry
            if leastRecentEntry == nil {
                leastRecentEntry = entry
            }
        }

        private func remove(_ entry: Entry) {
            entries.removeValue(forKey: entry.key)
            detach(entry)
        }

        private func detach(_ entry: Entry) {
            let previous = entry.previous
            let next = entry.next
            previous?.next = next
            next?.previous = previous

            if mostRecentEntry === entry {
                mostRecentEntry = next
            }
            if leastRecentEntry === entry {
                leastRecentEntry = previous
            }

            entry.previous = nil
            entry.next = nil
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
