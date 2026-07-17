//
//  NativeImage.swift
//  MarkdownKit
//
//  Public typealias for the platform image type. Hosted in `Math/` because
//  that subsystem first introduced the alias, but consumed across the package
//  (Mermaid adapter, image attachment builder, math adapter).
//

#if canImport(UIKit)
import UIKit
typealias NativeImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias NativeImage = NSImage
#endif
