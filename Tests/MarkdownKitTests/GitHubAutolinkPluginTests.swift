import XCTest
import Markdown
@testable import MarkdownKit

private final class ImmutableMarkdownAutolinkResolver: MarkdownAutolinkResolver {
    let mentionBaseURL: String
    let issueBaseURL: String
    let commitBaseURL: String

    init(
        mentionBaseURL: String = "https://github.com",
        issueBaseURL: String = "https://github.com/owner/repo/issues",
        commitBaseURL: String = "https://github.com/owner/repo/commit"
    ) {
        self.mentionBaseURL = mentionBaseURL
        self.issueBaseURL = issueBaseURL
        self.commitBaseURL = commitBaseURL
    }

    func resolveMention(username: String) -> URL? {
        URL(string: "\(mentionBaseURL)/\(username)")
    }

    func resolveReference(reference: String) -> URL? {
        if reference.contains("/") {
            return URL(string: "\(mentionBaseURL)/\(reference)")
        }

        let issueNumber = reference.hasPrefix("#") ? String(reference.dropFirst()) : reference
        return URL(string: "\(issueBaseURL)/\(issueNumber)")
    }

    func resolveCommit(sha: String) -> URL? {
        URL(string: "\(commitBaseURL)/\(sha)")
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: Self.self))
        hasher.combine(mentionBaseURL)
        hasher.combine(issueBaseURL)
        hasher.combine(commitBaseURL)
    }
}

private final class RetentionProbeAutolinkResolver: MarkdownAutolinkResolver {
    let token: String

    init(token: String) {
        self.token = token
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: Self.self))
        hasher.combine(token)
    }
}

final class GitHubAutolinkPluginTests: XCTestCase {
    func testMentionsAreExtractedWithResolver() {
        let textNode = TextNode(range: nil, text: "Hello @user123 and @test-user!")
        let resolver = ImmutableMarkdownAutolinkResolver()
        let plugin = GitHubAutolinkPlugin(resolver: resolver)

        let result = plugin.visit([textNode])

        XCTAssertEqual(result.count, 5)
        XCTAssertEqual((result[0] as? TextNode)?.text, "Hello ")

        let link1 = result[1] as? LinkNode
        XCTAssertNotNil(link1)
        XCTAssertEqual(link1?.destination, "https://github.com/user123")
        XCTAssertEqual((link1?.children.first as? TextNode)?.text, "@user123")

        XCTAssertEqual((result[2] as? TextNode)?.text, " and ")

        let link2 = result[3] as? LinkNode
        XCTAssertNotNil(link2)
        XCTAssertEqual(link2?.destination, "https://github.com/test-user")
        XCTAssertEqual((link2?.children.first as? TextNode)?.text, "@test-user")

        XCTAssertEqual((result[4] as? TextNode)?.text, "!")
    }

    func testIssuesAreExtractedWithResolver() {
        let textNode = TextNode(range: nil, text: "Fixes #42 and apple/swift#1000")
        let resolver = ImmutableMarkdownAutolinkResolver()
        let plugin = GitHubAutolinkPlugin(resolver: resolver)

        let result = plugin.visit([textNode])

        XCTAssertEqual(result.count, 4)

        let link1 = result[1] as? LinkNode
        XCTAssertEqual(link1?.destination, "https://github.com/owner/repo/issues/42")

        let link2 = result[3] as? LinkNode
        XCTAssertEqual(link2?.destination, "https://github.com/apple/swift#1000")
    }

    func testCommitSHAsAreExtractedWithResolver() {
        let textNode = TextNode(range: nil, text: "Merge commit 1a2b3c4d5e6f today")
        let resolver = ImmutableMarkdownAutolinkResolver()
        let plugin = GitHubAutolinkPlugin(resolver: resolver)

        let result = plugin.visit([textNode])

        XCTAssertEqual(result.count, 3)

        let link1 = result[1] as? LinkNode
        XCTAssertEqual(link1?.destination, "https://github.com/owner/repo/commit/1a2b3c4d5e6f")
        XCTAssertTrue(link1?.children.first is InlineCodeNode)
        XCTAssertEqual((link1?.children.first as? InlineCodeNode)?.code, "1a2b3c4d5e6f")
    }

    func testNilResolverUsesFallbackDestinationsForMentionReferenceAndCommit() {
        let textNode = TextNode(range: nil, text: "Ping @octocat in #42 via f81d4fa")
        let plugin = GitHubAutolinkPlugin(resolver: nil)

        let result = plugin.visit([textNode])

        XCTAssertEqual(result.count, 6)
        XCTAssertEqual((result[1] as? LinkNode)?.destination, "x-mention://octocat")
        XCTAssertEqual((result[3] as? LinkNode)?.destination, "x-reference://#42")
        XCTAssertEqual((result[5] as? LinkNode)?.destination, "x-commit://f81d4fa")
        XCTAssertTrue((result[5] as? LinkNode)?.children.first is InlineCodeNode)
    }

    func testMixedExtraction() {
        let resolver = ImmutableMarkdownAutolinkResolver()
        let parser = MarkdownParser(plugins: [GitHubAutolinkPlugin(resolver: resolver)])

        let markdown = "Hello @Anyuan, please check #123 and commit f81d4fa!"
        let document = parser.parse(markdown)

        guard let paragraph = document.children.first as? ParagraphNode else {
            XCTFail("Expected paragraph node")
            return
        }

        XCTAssertEqual(paragraph.children.count, 7)
        XCTAssertEqual((paragraph.children[0] as? TextNode)?.text, "Hello ")
        XCTAssertEqual((paragraph.children[1] as? LinkNode)?.destination, "https://github.com/Anyuan")
        XCTAssertEqual((paragraph.children[2] as? TextNode)?.text, ", please check ")
        XCTAssertEqual((paragraph.children[3] as? LinkNode)?.destination, "https://github.com/owner/repo/issues/123")
        XCTAssertEqual((paragraph.children[4] as? TextNode)?.text, " and commit ")
        XCTAssertEqual((paragraph.children[5] as? LinkNode)?.destination, "https://github.com/owner/repo/commit/f81d4fa")
        XCTAssertEqual((paragraph.children[6] as? TextNode)?.text, "!")
    }

    func testNoAutolinkMatchPreservesOriginalTextNodeIdentity() {
        let textNode = TextNode(range: nil, text: "Just plain text")
        let plugin = GitHubAutolinkPlugin(resolver: nil)

        let result = plugin.visit([textNode])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual((result[0] as? TextNode)?.text, "Just plain text")
        XCTAssertEqual(result[0].id, textNode.id)
    }

    func testAllDecimalSevenDigitRunIsNotAutolinkedAsCommit() {
        let textNode = TextNode(range: nil, text: "Order 1234567 shipped")
        let plugin = GitHubAutolinkPlugin(resolver: nil)

        let result = plugin.visit([textNode])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual((result[0] as? TextNode)?.text, "Order 1234567 shipped")
        XCTAssertEqual(result[0].id, textNode.id)
    }

    func testAllDecimalFortyDigitRunIsNotAutolinkedAsCommit() {
        let fortyDigits = String(repeating: "1234567890", count: 4)
        XCTAssertEqual(fortyDigits.count, 40)

        let textNode = TextNode(range: nil, text: "ID \(fortyDigits) done")
        let plugin = GitHubAutolinkPlugin(resolver: nil)

        let result = plugin.visit([textNode])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual((result[0] as? TextNode)?.text, "ID \(fortyDigits) done")
        XCTAssertEqual(result[0].id, textNode.id)
    }

    func testSevenCharacterLetterContainingSHAStillAutolinks() {
        let textNode = TextNode(range: nil, text: "Merge commit f81d4fa done")
        let plugin = GitHubAutolinkPlugin(resolver: nil)

        let result = plugin.visit([textNode])

        XCTAssertEqual(result.count, 3)
        let link = result[1] as? LinkNode
        XCTAssertNotNil(link)
        XCTAssertEqual(link?.destination, "x-commit://f81d4fa")
        XCTAssertTrue(link?.children.first is InlineCodeNode)
        XCTAssertEqual((link?.children.first as? InlineCodeNode)?.code, "f81d4fa")
    }

    func testLongNumericIssueReferenceStillResolvesAsReference() {
        let textNode = TextNode(range: nil, text: "Fixes #1234567 and apple/swift#1234567")
        let plugin = GitHubAutolinkPlugin(resolver: nil)

        let result = plugin.visit([textNode])

        XCTAssertEqual(result.count, 4)
        XCTAssertEqual((result[1] as? LinkNode)?.destination, "x-reference://#1234567")
        XCTAssertEqual((result[3] as? LinkNode)?.destination, "x-reference://apple/swift#1234567")
    }

    func testPluginStronglyRetainsResolverForPluginLifetime() {
        weak var weakResolver: RetentionProbeAutolinkResolver?
        var plugin: GitHubAutolinkPlugin?

        do {
            var resolver: RetentionProbeAutolinkResolver? = RetentionProbeAutolinkResolver(token: "retain")
            weakResolver = resolver
            plugin = GitHubAutolinkPlugin(resolver: resolver)
            resolver = nil

            XCTAssertNotNil(weakResolver)
            XCTAssertNotNil(plugin?.resolver)
        }

        plugin = nil
        XCTAssertNil(weakResolver)
    }

    func testPluginFingerprintTracksResolverPresenceAndConfiguration() {
        let noResolverFingerprint = fingerprint(of: GitHubAutolinkPlugin(resolver: nil))

        let baselineResolver = ImmutableMarkdownAutolinkResolver(
            mentionBaseURL: "https://github.example.com",
            issueBaseURL: "https://github.example.com/owner/repo/issues",
            commitBaseURL: "https://github.example.com/owner/repo/commit"
        )
        let sameConfigResolver = ImmutableMarkdownAutolinkResolver(
            mentionBaseURL: "https://github.example.com",
            issueBaseURL: "https://github.example.com/owner/repo/issues",
            commitBaseURL: "https://github.example.com/owner/repo/commit"
        )
        let differentConfigResolver = ImmutableMarkdownAutolinkResolver(
            mentionBaseURL: "https://github.example.com",
            issueBaseURL: "https://github.example.com/apple/swift/issues",
            commitBaseURL: "https://github.example.com/apple/swift/commit"
        )

        let baselineFingerprint = fingerprint(of: GitHubAutolinkPlugin(resolver: baselineResolver))
        let sameConfigFingerprint = fingerprint(of: GitHubAutolinkPlugin(resolver: sameConfigResolver))
        let differentConfigFingerprint = fingerprint(of: GitHubAutolinkPlugin(resolver: differentConfigResolver))

        XCTAssertNotEqual(noResolverFingerprint, baselineFingerprint)
        XCTAssertEqual(baselineFingerprint, sameConfigFingerprint)
        XCTAssertNotEqual(baselineFingerprint, differentConfigFingerprint)
    }

    private func fingerprint(of plugin: GitHubAutolinkPlugin) -> Int {
        var hasher = Hasher()
        plugin.cacheFingerprint(into: &hasher)
        return hasher.finalize()
    }
}
