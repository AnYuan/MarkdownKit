import XCTest
@testable import MarkdownKit

@available(*, deprecated, message: "Compile-only migration shim coverage")
private final class LegacyAutolinkResolver: MarkdownContextDelegate {}

@available(*, deprecated, message: "Compile-only migration shim coverage")
private func _compileLegacyAutolinkMigrationShims() {
    let resolver: MarkdownContextDelegate? = LegacyAutolinkResolver()
    _ = GitHubAutolinkPlugin(delegate: resolver)
    _ = MarkdownKitEngine.defaultPlugins(
        contextDelegate: resolver,
        includeGitHubAutolinks: true
    )
    _ = MarkdownKitEngine.makeParser(
        contextDelegate: resolver,
        includeGitHubAutolinks: true
    )
}

private final class EngineAutolinkResolver: MarkdownAutolinkResolver {
    let ownerRepo: String

    init(ownerRepo: String) {
        self.ownerRepo = ownerRepo
    }

    func resolveMention(username: String) -> URL? {
        URL(string: "https://github.com/\(username)")
    }

    func resolveReference(reference: String) -> URL? {
        if reference.contains("/") {
            return URL(string: "https://github.com/\(reference)")
        }

        let issueNumber = reference.hasPrefix("#") ? String(reference.dropFirst()) : reference
        return URL(string: "https://github.com/\(ownerRepo)/issues/\(issueNumber)")
    }

    func resolveCommit(sha: String) -> URL? {
        URL(string: "https://github.com/\(ownerRepo)/commit/\(sha)")
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: Self.self))
        hasher.combine(ownerRepo)
    }
}

private func linkDestinations(in document: DocumentNode) -> [String] {
    guard let paragraph = document.children.first as? ParagraphNode else {
        return []
    }
    return paragraph.children.compactMap { ($0 as? LinkNode)?.destination }
}

final class MarkdownKitTests: XCTestCase {
    
    func testBasicCommonMarkParsing() throws {
        let parser = MarkdownParser()
        let markdownString = """
        # Hello World
        This is a paragraph.
        """
        
        // Measure the pure AST parsing performance to adhere to Section 4 / 6 of PRD
        var docNode: DocumentNode!
        PerformanceProfiler.measure(.astParsing) {
            docNode = parser.parse(markdownString)
        }
        
        XCTAssertEqual(docNode.children.count, 2)
        
        // Test Header Node
        let header = docNode.children[0] as? HeaderNode
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.level, 1)
        XCTAssertEqual(header?.children.count, 1)
        let headerText = header?.children[0] as? TextNode
        XCTAssertEqual(headerText?.text, "Hello World")
        
        // Test Paragraph Node
        let paragraph = docNode.children[1] as? ParagraphNode
        XCTAssertNotNil(paragraph)
        XCTAssertEqual(paragraph?.children.count, 1)
        let paragraphText = paragraph?.children[0] as? TextNode
        XCTAssertEqual(paragraphText?.text, "This is a paragraph.")
    }

    func testCodeAndImageGFMParsing() throws {
        let parser = MarkdownParser()
        let markdownString = """
        ```swift
        print("Hello")
        ```
        ![My Image](https://example.com/img.png "Optional Title")
        """
        
        let docNode = parser.parse(markdownString)
        XCTAssertEqual(docNode.children.count, 2)
        
        // Test Code Block
        let codeBlock = docNode.children[0] as? CodeBlockNode
        XCTAssertNotNil(codeBlock)
        XCTAssertEqual(codeBlock?.language, "swift")
        XCTAssertEqual(codeBlock?.code, "print(\"Hello\")\n") // cmark raw code blocks include a trailing newline
        
        // Test Image (contained within a Paragraph block implicitly by swift-markdown)
        let paragraph = docNode.children[1] as? ParagraphNode
        XCTAssertNotNil(paragraph)
        
        let image = paragraph?.children[0] as? ImageNode
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.source, "https://example.com/img.png")
        XCTAssertEqual(image?.altText, "My Image")
        XCTAssertEqual(image?.title, "Optional Title")
    }

    func testEngineDefaultPluginsIncludeCorePipeline() {
        let plugins = MarkdownKitEngine.defaultPlugins()
        XCTAssertEqual(plugins.count, 3)
        XCTAssertTrue(plugins.contains { $0 is DetailsExtractionPlugin })
        XCTAssertTrue(plugins.contains { $0 is DiagramExtractionPlugin })
        XCTAssertTrue(plugins.contains { $0 is MathExtractionPlugin })
    }

    func testEngineDefaultPluginsAppendAutolinkPluginInExpectedOrderAndForwardResolver() {
        let resolver = EngineAutolinkResolver(ownerRepo: "owner/repo")
        let plugins = MarkdownKitEngine.defaultPlugins(
            autolinkResolver: resolver,
            includeGitHubAutolinks: true
        )

        XCTAssertEqual(plugins.count, 4)
        XCTAssertTrue(plugins[0] is DetailsExtractionPlugin)
        XCTAssertTrue(plugins[1] is DiagramExtractionPlugin)
        XCTAssertTrue(plugins[2] is MathExtractionPlugin)

        guard let autolinkPlugin = plugins[3] as? GitHubAutolinkPlugin else {
            XCTFail("Expected GitHubAutolinkPlugin at pipeline tail")
            return
        }

        guard let forwardedResolver = autolinkPlugin.resolver as? EngineAutolinkResolver else {
            XCTFail("Expected resolver forwarding")
            return
        }
        XCTAssertTrue(forwardedResolver === resolver)
    }

    func testEngineMakeParserUsesAutolinkResolverAndDefaultPluginOrder() {
        let resolver = EngineAutolinkResolver(ownerRepo: "apple/swift")
        let parser = MarkdownKitEngine.makeParser(
            autolinkResolver: resolver,
            includeGitHubAutolinks: true
        )

        XCTAssertEqual(parser.plugins.count, 4)
        XCTAssertTrue(parser.plugins[0] is DetailsExtractionPlugin)
        XCTAssertTrue(parser.plugins[1] is DiagramExtractionPlugin)
        XCTAssertTrue(parser.plugins[2] is MathExtractionPlugin)
        XCTAssertTrue(parser.plugins[3] is GitHubAutolinkPlugin)

        let document = parser.parse("Hello @octocat, fixes #123 with f81d4fa")
        XCTAssertEqual(
            linkDestinations(in: document),
            [
                "https://github.com/octocat",
                "https://github.com/apple/swift/issues/123",
                "https://github.com/apple/swift/commit/f81d4fa"
            ]
        )
    }

    func testDetachedTaskCanConstructAndUseParserWithSendableOutput() async {
        let destinations: [String] = await Task.detached {
            let resolver = EngineAutolinkResolver(ownerRepo: "owner/repo")
            let parser = MarkdownKitEngine.makeParser(
                autolinkResolver: resolver,
                includeGitHubAutolinks: true
            )
            let document = parser.parse("Ping @octocat about #42 and f81d4fa")
            return linkDestinations(in: document)
        }.value

        XCTAssertEqual(
            destinations,
            [
                "https://github.com/octocat",
                "https://github.com/owner/repo/issues/42",
                "https://github.com/owner/repo/commit/f81d4fa"
            ]
        )
    }

    func testEngineConvenienceLayoutReturnsChildren() async {
        let layout = await MarkdownKitEngine.layout(
            markdown: "# Title\n\nParagraph text",
            constrainedToWidth: 400
        )

        XCTAssertEqual(layout.children.count, 2)
        XCTAssertTrue(layout.children[0].node is HeaderNode)
        XCTAssertTrue(layout.children[1].node is ParagraphNode)
    }
}
