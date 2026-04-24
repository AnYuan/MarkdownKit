//
//  LayoutSolver.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A solver that traverses a structured `MarkdownNode` tree and calculates
/// exact visual styling and bounding frames for each element.
///
/// - Important: Must only be executed on a background queue.
public final class LayoutSolver: @unchecked Sendable {
    
    private let textCalculator: TextKitCalculator
    private let arithmeticCalculator: ArithmeticTextCalculator
    private let cache: LayoutCache
    private let builder: AttributedStringBuilder
    private let cacheVariantHash: Int
    
    public init(
        theme: Theme = .default,
        cache: LayoutCache = LayoutCache(),
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        mathAdapter: (any MathRenderingAdapter)? = nil,
        imageLoadingPolicy: ImageLoadingPolicy = .default
    ) {
        self.textCalculator = TextKitCalculator()
        self.arithmeticCalculator = ArithmeticTextCalculator()
        self.cache = cache
        self.cacheVariantHash = Self.makeCacheVariantHash(
            theme: theme,
            diagramRegistry: diagramRegistry,
            mathAdapter: mathAdapter ?? DefaultMathRenderingAdapter(),
            imageLoadingPolicy: imageLoadingPolicy
        )
        let highlighter = SplashHighlighter(theme: theme)
        self.builder = AttributedStringBuilder(
            theme: theme,
            highlighter: highlighter,
            diagramRegistry: diagramRegistry,
            mathAdapter: mathAdapter ?? DefaultMathRenderingAdapter(),
            imageLoadingPolicy: imageLoadingPolicy
        )
    }
    
    private final class SendableBox<T>: @unchecked Sendable {
        var value: T?
        init(_ value: T? = nil) { self.value = value }
    }

    private static func makeCacheVariantHash(
        theme: Theme,
        diagramRegistry: DiagramAdapterRegistry,
        mathAdapter: any MathRenderingAdapter,
        imageLoadingPolicy: ImageLoadingPolicy
    ) -> Int {
        var hasher = Hasher()
        combineTheme(theme, into: &hasher)
        hasher.combine(diagramRegistry.cacheFingerprint)
        hasher.combine(String(reflecting: type(of: mathAdapter)))
        hasher.combine(imageLoadingPolicy.cacheFingerprint)
        return hasher.finalize()
    }

    private static func combineTheme(_ theme: Theme, into hasher: inout Hasher) {
        combineTypography(theme.typography.header1, into: &hasher)
        combineTypography(theme.typography.header2, into: &hasher)
        combineTypography(theme.typography.header3, into: &hasher)
        combineTypography(theme.typography.paragraph, into: &hasher)
        combineTypography(theme.typography.codeBlock, into: &hasher)

        combineColorToken(theme.colors.textColor, into: &hasher)
        combineColorToken(theme.colors.codeColor, into: &hasher)
        combineColorToken(theme.colors.inlineCodeColor, into: &hasher)
        combineColorToken(theme.colors.tableColor, into: &hasher)
        combineColorToken(theme.colors.linkColor, into: &hasher)
        combineColorToken(theme.colors.blockQuoteColor, into: &hasher)
        combineColorToken(theme.colors.thematicBreakColor, into: &hasher)

        combineCodeBlockStyle(theme.codeBlock, into: &hasher)
        hasher.combine(Double(theme.blockQuote.indent))
        hasher.combine(theme.blockQuote.barCharacter)
        hasher.combine(theme.list.bulletCharacter)
        hasher.combine(theme.list.checkedCharacter)
        hasher.combine(theme.list.uncheckedCharacter)
        hasher.combine(Double(theme.list.nestedIndentDelta))
        hasher.combine(theme.details.openDisclosure)
        hasher.combine(theme.details.closedDisclosure)
        combineTableStyle(theme.table, into: &hasher)
        combineSyntaxColors(theme.syntaxColors, into: &hasher)
        hasher.combine(Double(theme.highlight.cornerRadius))
        hasher.combine(Double(theme.highlight.darkModeAlpha))
        hasher.combine(Double(theme.highlight.lightModeAlpha))
        hasher.combine(Double(theme.highlight.insetDX))
        hasher.combine(Double(theme.highlight.insetDY))
        hasher.combine(Double(theme.highlight.fadeInDuration))
        hasher.combine(Double(theme.highlight.fadeOutDuration))
        hasher.combine(Double(theme.thematicBreak.paddingTop))
        hasher.combine(Double(theme.thematicBreak.paddingBottom))
        hasher.combine(Double(theme.thematicBreak.dividerHeight))
    }

    private static func combineTypography(_ token: TypographyToken, into hasher: inout Hasher) {
        combineFont(token.font, into: &hasher)
        hasher.combine(Double(token.lineHeightMultiple))
        hasher.combine(Double(token.paragraphSpacing))
    }

    private static func combineColorToken(_ token: ColorToken, into hasher: inout Hasher) {
        combineColor(token.foreground, into: &hasher)
        combineColor(token.background, into: &hasher)
    }

    private static func combineCodeBlockStyle(_ style: Theme.CodeBlockStyle, into hasher: inout Hasher) {
        hasher.combine(Double(style.cornerRadius))
        hasher.combine(Double(style.layoutTotalInset))
        hasher.combine(Double(style.viewPadding))
        combineFont(style.labelFont, into: &hasher)
        hasher.combine(Double(style.labelParagraphSpacing))
        hasher.combine(Double(style.inlineCodeFontSizeRatio))
        hasher.combine(Double(style.inlineCodeMinFontSize))
        hasher.combine(Double(style.copyButtonSize))
        hasher.combine(Double(style.copyButtonCornerRadius))
        hasher.combine(Double(style.copyButtonMargin))
        hasher.combine(Double(style.copyButtonIconSize))
        hasher.combine(Double(style.macOSCornerRadius))
        hasher.combine(Double(style.macOSTextContainerInset.width))
        hasher.combine(Double(style.macOSTextContainerInset.height))
    }

    private static func combineTableStyle(_ style: Theme.TableStyle, into hasher: inout Hasher) {
        hasher.combine(Double(style.cornerRadius))
        hasher.combine(Double(style.borderWidth))
        hasher.combine(Double(style.cellPaddingH))
        hasher.combine(Double(style.cellPaddingV))
        hasher.combine(Double(style.dividerHeight))
        hasher.combine(Double(style.fontSize))
        hasher.combine(Double(style.uiKitHorizontalInset))
        hasher.combine(Double(style.appKitHorizontalPadding))
        hasher.combine(Double(style.appKitBorderAllowance))
        hasher.combine(Double(style.minimumReadableColumnWidth))
        hasher.combine(Double(style.cellParagraphSpacing))
        hasher.combine(style.narrowFallbackMaxChars)
        hasher.combine(Double(style.alternatingRowAlpha))
        hasher.combine(Double(style.separatorAlpha))
    }

    private static func combineSyntaxColors(_ colors: Theme.SyntaxColors, into hasher: inout Hasher) {
        combineColor(colors.keyword, into: &hasher)
        combineColor(colors.string, into: &hasher)
        combineColor(colors.type, into: &hasher)
        combineColor(colors.call, into: &hasher)
        combineColor(colors.number, into: &hasher)
        combineColor(colors.comment, into: &hasher)
        combineColor(colors.property, into: &hasher)
        combineColor(colors.dotAccess, into: &hasher)
        combineColor(colors.preprocessing, into: &hasher)
    }

    private static func combineFont(_ font: Font, into hasher: inout Hasher) {
        hasher.combine(font.fontName)
        hasher.combine(Double(font.pointSize))
        #if canImport(UIKit)
        hasher.combine(font.fontDescriptor.symbolicTraits.rawValue)
        #elseif canImport(AppKit)
        hasher.combine(font.fontDescriptor.symbolicTraits.rawValue)
        #endif
    }

    private static func combineColor(_ color: Color, into hasher: inout Hasher) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        #if canImport(UIKit)
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            hasher.combine(Double(red))
            hasher.combine(Double(green))
            hasher.combine(Double(blue))
            hasher.combine(Double(alpha))
        } else {
            hasher.combine(String(describing: color))
        }
        #elseif canImport(AppKit)
        if let rgb = color.usingColorSpace(.sRGB) {
            rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            hasher.combine(Double(red))
            hasher.combine(Double(green))
            hasher.combine(Double(blue))
            hasher.combine(Double(alpha))
        } else {
            hasher.combine(String(describing: color))
        }
        #endif
    }

    /// Recursively calculates the layout for a node and all its children.
    ///
    /// - Parameters:
    ///   - node: The root AST node.
    ///   - maxWidth: The maximum layout boundaries (e.g. view width).
    /// - Returns: A fully calculated `LayoutResult` tree holding sizes and attributed strings.
    public func solve(node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) async -> LayoutResult {
        // Yield to the system to keep scroll rendering incredibly smooth for giant files
        // This is the cooperative multitasking layer
        await Task.yield()

        // Return instantly if we already calculated this specific layout at this width
        if let cached = cache.getLayout(for: node, constrainedToWidth: maxWidth, variantHash: cacheVariantHash) {
            return cached
        }

        #if canImport(UIKit) && !os(watchOS)
        // Card-style table rendering on iOS: bypass TextKit, draw directly via CGContext
        if let table = node as? TableNode {
            let result = solveTableCard(table: table, constrainedToWidth: maxWidth)
            cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: cacheVariantHash)
            return result
        }

        // Thematic break: draw a hairline matching legacy DividerAttachment
        if node is ThematicBreakNode {
            let result = solveThematicBreak(node: node, constrainedToWidth: maxWidth)
            cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: cacheVariantHash)
            return result
        }
        #endif


        // 1. Convert AST to styled NSAttributedString based on Theme
        let styledString: NSAttributedString
        var size: CGSize

        // Special handling for nodes that have internal padding in their UI representation
        if let code = node as? CodeBlockNode {
            styledString = builder.buildCodeBlockAttributedString(from: code)

            // TextKit needs to know that we inset the container 8pts horizontally by the UI view
            // to accurately wrap the string if it's too long.
            let totalInset = builder.theme.codeBlock.layoutTotalInset
            let insets = CGSize(width: totalInset, height: totalInset)
            size = textCalculator.calculateSize(
                for: styledString,
                constrainedToWidth: max(0, maxWidth - insets.width)
            )
            size.width += insets.width
            size.height += insets.height

        } else if let diagram = node as? DiagramNode {
            styledString = await builder.buildDiagramAttributedString(from: diagram)

            let totalInset = builder.theme.codeBlock.layoutTotalInset
            let insets = CGSize(width: totalInset, height: totalInset)
            size = textCalculator.calculateSize(
                for: styledString,
                constrainedToWidth: max(0, maxWidth - insets.width)
            )
            size.width += insets.width
            size.height += insets.height

        } else {
            styledString = await builder.buildString(for: node, constrainedToWidth: maxWidth)
            
            if shouldUseArithmeticLayout(for: node, styledString: styledString) {
                size = arithmeticCalculator.calculateSize(for: styledString, constrainedToWidth: maxWidth)
            } else {
                size = textCalculator.calculateSize(for: styledString, constrainedToWidth: maxWidth)
            }
        }

        // 3. Recurse down children (if they represent separate visual block elements)
        // For basic implementation, we assume paragraphs/headers handle their own inline children.
        // But for Documents, we must layout all top-level blocks.
        var childLayouts: [LayoutResult] = []

        if let doc = node as? DocumentNode {
            for child in doc.children {
                childLayouts.append(await solve(node: child, constrainedToWidth: maxWidth))
            }
        }

        // strictly immutable frame container
        let result = LayoutResult(
            node: node,
            size: size,
            attributedString: styledString,
            children: childLayouts
        )

        // Memoize the result
        cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: cacheVariantHash)

        return result
    }

    /// Synchronous variant of `solve` that avoids Swift concurrency entirely.
    /// Uses `buildStringSync` (cached math / fallback text, no async rendering).
    /// Safe to call from the main thread without RunLoop polling.
    public func solveSync(node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) -> LayoutResult {
        if let cached = cache.getLayout(for: node, constrainedToWidth: maxWidth, variantHash: cacheVariantHash) {
            return cached
        }

        #if canImport(UIKit) && !os(watchOS)
        if let table = node as? TableNode {
            let result = solveTableCard(table: table, constrainedToWidth: maxWidth)
            cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: cacheVariantHash)
            return result
        }

        if node is ThematicBreakNode {
            let result = solveThematicBreak(node: node, constrainedToWidth: maxWidth)
            cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: cacheVariantHash)
            return result
        }
        #endif

        let styledString: NSAttributedString
        var size: CGSize

        if let code = node as? CodeBlockNode {
            styledString = builder.buildCodeBlockAttributedString(from: code)
            let totalInset = builder.theme.codeBlock.layoutTotalInset
            let insets = CGSize(width: totalInset, height: totalInset)
            size = textCalculator.calculateSize(
                for: styledString,
                constrainedToWidth: max(0, maxWidth - insets.width)
            )
            size.width += insets.width
            size.height += insets.height
        } else {
            styledString = builder.buildStringSync(for: node, constrainedToWidth: maxWidth)
            
            if shouldUseArithmeticLayout(for: node, styledString: styledString) {
                size = arithmeticCalculator.calculateSize(for: styledString, constrainedToWidth: maxWidth)
            } else {
                size = textCalculator.calculateSize(for: styledString, constrainedToWidth: maxWidth)
            }
        }

        var childLayouts: [LayoutResult] = []
        if let doc = node as? DocumentNode {
            for child in doc.children {
                childLayouts.append(solveSync(node: child, constrainedToWidth: maxWidth))
            }
        }

        let result = LayoutResult(
            node: node,
            size: size,
            attributedString: styledString,
            children: childLayouts
        )
        cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: cacheVariantHash)
        return result
    }

    // MARK: - Thematic Break Layout (iOS only)

    #if canImport(UIKit) && !os(watchOS)
    private func solveThematicBreak(node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) -> LayoutResult {
        let paddingTop = builder.theme.thematicBreak.paddingTop
        let paddingBottom = builder.theme.thematicBreak.paddingBottom
        let dividerHeight = builder.theme.thematicBreak.dividerHeight
        let totalHeight = paddingTop + dividerHeight + paddingBottom
        let totalSize = CGSize(width: maxWidth, height: totalHeight)

        let resolvedColor = builder.theme.colors.thematicBreakColor.foreground.cgColor

        let customDraw: @Sendable (CGContext, CGSize) -> Void = { context, size in
            context.saveGState()
            // Actual hairline
            context.setFillColor(resolvedColor)
            context.fill(CGRect(x: 0, y: paddingTop, width: size.width, height: dividerHeight))
            context.restoreGState()
        }

        return LayoutResult(
            node: node,
            size: totalSize,
            attributedString: nil,
            children: [],
            customDraw: customDraw
        )
    }
    #endif

    // MARK: - Table Card Layout (iOS only)

    #if canImport(UIKit) && !os(watchOS)
    /// Produces a `LayoutResult` for a table node that uses CGContext card rendering
    /// instead of TextKit. The `customDraw` closure captures the pre-computed layout
    /// and resolved colors so that rasterization is fully thread-safe.
    private func solveTableCard(table: TableNode, constrainedToWidth maxWidth: CGFloat) -> LayoutResult {
        let layout = TableCardRenderer.computeLayout(
            from: table,
            theme: builder.theme,
            constrainedToWidth: maxWidth
        )

        // Resolve UIColor -> CGColor on the current thread (which has trait collection context).
        let resolvedColors = TableCardRenderer.ResolvedColors.resolve(from: builder.theme)

        let customDraw: @Sendable (CGContext, CGSize) -> Void = { context, size in
            TableCardRenderer.draw(
                layout: layout,
                resolvedColors: resolvedColors,
                in: context,
                size: size
            )
        }

        return LayoutResult(
            node: table,
            size: layout.totalSize,
            attributedString: nil,
            children: [],
            customDraw: customDraw
        )
    }
    #endif

    // MARK: - Routing Helpers

    /// Determines if a node is a simple text block that can be safely routed
    /// to the lock-free `ArithmeticTextCalculator`.
    private func shouldUseArithmeticLayout(for node: MarkdownNode, styledString: NSAttributedString) -> Bool {
        isPureTextBlock(node) && arithmeticCalculator.profile(for: styledString).supportsArithmeticLayout
    }

    private func isPureTextBlock(_ node: MarkdownNode) -> Bool {
        // Only route paragraph and header nodes for now
        guard node is ParagraphNode || node is HeaderNode else {
            return false
        }
        
        var hasAttachments = false
        
        func traverse(_ n: MarkdownNode) {
            if hasAttachments { return }
            
            // If we find any of these, we must use TextKit for accurate layout
            if n is ImageNode || 
               n is MathNode || 
               n is DiagramNode || 
               n is TableNode || 
               n is CodeBlockNode ||
               n is DetailsNode {
                hasAttachments = true
                return
            }
            
            for child in n.children {
                traverse(child)
            }
        }
        
        traverse(node)
        return !hasAttachments
    }
}
