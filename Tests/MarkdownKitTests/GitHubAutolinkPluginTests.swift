import XCTest
import Markdown
@testable import MarkdownKit

final class MockMarkdownContextDelegate: MarkdownContextDelegate {
    func resolveMention(username: String) -> URL? {
        return URL(string: "https://github.com/\(username)")
    }
    
    func resolveReference(reference: String) -> URL? {
        if reference.contains("/") {
            return URL(string: "https://github.com/\(reference)")
        } else {
            return URL(string: "https://github.com/owner/repo/issues/\(reference.dropFirst())") // remove '#'
        }
    }
    
    func resolveCommit(sha: String) -> URL? {
        return URL(string: "https://github.com/owner/repo/commit/\(sha)")
    }
    
    func didToggleCheckbox(isChecked: Bool, at range: NSRange) {}
    func didTriggerAction(withID actionID: String) {}
}

final class GitHubAutolinkPluginTests: XCTestCase {
    
    func testMentionsAreExtracted() {
        let textNode = TextNode(range: nil, text: "Hello @user123 and @test-user!")
        let delegate = MockMarkdownContextDelegate()
        let plugin = GitHubAutolinkPlugin(delegate: delegate)
        
        let result = plugin.visit([textNode])
        
        XCTAssertEqual(result.count, 5) // "Hello ", Link, " and ", Link, "!"
        
        // Check first text
        XCTAssertEqual((result[0] as? TextNode)?.text, "Hello ")
        
        // Check first link
        let link1 = result[1] as? LinkNode
        XCTAssertNotNil(link1)
        XCTAssertEqual(link1?.destination, "https://github.com/user123")
        XCTAssertEqual((link1?.children.first as? TextNode)?.text, "@user123")
        
        // Check middle text
        XCTAssertEqual((result[2] as? TextNode)?.text, " and ")
        
        // Check second link
        let link2 = result[3] as? LinkNode
        XCTAssertNotNil(link2)
        XCTAssertEqual(link2?.destination, "https://github.com/test-user")
        XCTAssertEqual((link2?.children.first as? TextNode)?.text, "@test-user")
        // "!" is captured in the trailing? Wait, let's look at the result.
        // If trailing "!" is not correctly appended we'll find out.
    }
    
    func testIssuesAreExtracted() {
        let textNode = TextNode(range: nil, text: "Fixes #42 and apple/swift#1000")
        let delegate = MockMarkdownContextDelegate()
        let plugin = GitHubAutolinkPlugin(delegate: delegate)
        
        let result = plugin.visit([textNode])
        
        // "Fixes ", Link(#42), " and ", Link(apple/swift#1000)
        XCTAssertEqual(result.count, 4)
        
        let link1 = result[1] as? LinkNode
        XCTAssertEqual(link1?.destination, "https://github.com/owner/repo/issues/42")
        
        let link2 = result[3] as? LinkNode
        XCTAssertEqual(link2?.destination, "https://github.com/apple/swift#1000")
    }
    
    func testCommitSHAsAreExtracted() {
        let textNode = TextNode(range: nil, text: "Merge commit 1a2b3c4d5e6f today")
        let delegate = MockMarkdownContextDelegate()
        let plugin = GitHubAutolinkPlugin(delegate: delegate)
        
        let result = plugin.visit([textNode])
        
        XCTAssertEqual(result.count, 3) // "Merge commit ", Link, " today"
        
        let link1 = result[1] as? LinkNode
        XCTAssertEqual(link1?.destination, "https://github.com/owner/repo/commit/1a2b3c4d5e6f")
        XCTAssertTrue(link1?.children.first is InlineCodeNode) // SHA defaults to inline code visually
        XCTAssertEqual((link1?.children.first as? InlineCodeNode)?.code, "1a2b3c4d5e6f")
    }
    
    func testMixedExtraction() {
        let delegate = MockMarkdownContextDelegate()
        let parser = MarkdownParser(plugins: [GitHubAutolinkPlugin(delegate: delegate)])
        
        let markdown = "Hello @Anyuan, please check #123 and commit f81d4fa!"
        let document = parser.parse(markdown)
        
        // The parser converts it to: Document -> Paragraph -> [Text, Link, Text, Link, Text, Link, Text]
        guard let p = document.children.first as? ParagraphNode else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(p.children.count, 7)
        XCTAssertEqual((p.children[0] as? TextNode)?.text, "Hello ")
        XCTAssertEqual((p.children[1] as? LinkNode)?.destination, "https://github.com/Anyuan")
        XCTAssertEqual((p.children[2] as? TextNode)?.text, ", please check ")
        XCTAssertEqual((p.children[3] as? LinkNode)?.destination, "https://github.com/owner/repo/issues/123")
        XCTAssertEqual((p.children[4] as? TextNode)?.text, " and commit ")
        XCTAssertEqual((p.children[5] as? LinkNode)?.destination, "https://github.com/owner/repo/commit/f81d4fa")
        XCTAssertEqual((p.children[6] as? TextNode)?.text, "!")
    }
}
