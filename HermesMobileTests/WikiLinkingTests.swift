import XCTest
@testable import HermesMobile

final class WikiLinkingTests: XCTestCase {
    func testWikilinkPreprocessorConvertsSimplePageLink() throws {
        let output = WikiWikilinkPreprocessor.replacingWikilinks(in: "See [[Project Radar]] next.")

        XCTAssertTrue(output.contains("[Project Radar]("))
        let url = try extractFirstURL(from: output)
        let route = try XCTUnwrap(WikiLinkResolver.resolve(url))
        XCTAssertEqual(route, WikiRoute(kind: .page(path: "Project Radar", title: "Project Radar")))
    }

    func testWikilinkPreprocessorPreservesSlashAndUnderscorePathsFromCronOutput() throws {
        let input = "Filed [[_agent/reports/2026-07-01-report-action-operator]] and [[Projects/Active/App Store Portfolio/Apps/Flow TV]]."
        let output = WikiWikilinkPreprocessor.replacingWikilinks(in: input)
        let urls = try extractURLs(from: output)

        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(
            WikiLinkResolver.resolve(urls[0]),
            WikiRoute(kind: .page(path: "_agent/reports/2026-07-01-report-action-operator", title: "2026 07 01 report action operator"))
        )
        XCTAssertEqual(
            WikiLinkResolver.resolve(urls[1]),
            WikiRoute(kind: .page(path: "Projects/Active/App Store Portfolio/Apps/Flow TV", title: "Flow TV"))
        )
    }

    func testWikilinkPreprocessorSupportsAlias() throws {
        let output = WikiWikilinkPreprocessor.replacingWikilinks(in: "Open [[Projects/Active/App Store Portfolio/README|portfolio overview]].")

        XCTAssertTrue(output.contains("[portfolio overview]("))
        let route = try XCTUnwrap(WikiLinkResolver.resolve(try extractFirstURL(from: output)))
        XCTAssertEqual(
            route,
            WikiRoute(kind: .page(path: "Projects/Active/App Store Portfolio/README", title: "portfolio overview"))
        )
    }

    func testWikilinkPreprocessorSkipsInlineCodeAndFencedCode() {
        let input = "Inline `[[Not a Link]]`\n\n```bash\ngrep -c \"[[page-name]]\" ~/wiki/index.md\n```\n\nBut [[Real Page]] works."
        let output = WikiWikilinkPreprocessor.replacingWikilinks(in: input)

        XCTAssertTrue(output.contains("`[[Not a Link]]`"))
        XCTAssertTrue(output.contains("[[page-name]]"))
        XCTAssertTrue(output.contains("[Real Page]("))
    }

    func testResolverMapsWikiAppsHTTPSLinksToAppRoute() throws {
        let url = try XCTUnwrap(URL(string: "https://wiki.sourcebottle.dev/apps/feedback-inbox"))

        XCTAssertEqual(
            WikiLinkResolver.resolve(url, wikiBaseURL: WikiSettings.defaultBaseURL),
            WikiRoute(kind: .app(path: "/apps/feedback-inbox"))
        )
    }

    func testResolverIgnoresForeignHTTPSLinks() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/apps/feedback-inbox"))

        XCTAssertNil(WikiLinkResolver.resolve(url, wikiBaseURL: WikiSettings.defaultBaseURL))
    }

    func testMarkdownCandidateURLsEncodePathComponentsAndKeepSlashHierarchy() throws {
        let urls = WikiURLBuilder.markdownCandidateURLs(
            for: "Projects/Active/App Store Portfolio/Apps/Flow TV",
            baseURL: WikiSettings.defaultBaseURL
        )

        XCTAssertEqual(
            urls.map(\.absoluteString),
            [
                "https://wiki.sourcebottle.dev/Projects/Active/App%20Store%20Portfolio/Apps/Flow%20TV.md",
                "https://wiki.sourcebottle.dev/Projects/Active/App%20Store%20Portfolio/Apps/Flow%20TV",
                "https://wiki.sourcebottle.dev/Projects/Active/App%20Store%20Portfolio/Apps/Flow%20TV/index.md"
            ]
        )
    }

    func testFormatterStripsFrontmatterAndAddsTitleWhenMissingHeading() {
        let raw = """
        ---
        title: Project Radar
        visibility: private
        ---

        Body text.
        """

        XCTAssertEqual(
            WikiMarkdownDocumentFormatter.displayMarkdown(from: raw, title: "Project Radar"),
            "# Project Radar\n\nBody text."
        )
    }

    func testWikiBrowserOpensGoogleOAuthExternally() throws {
        let authURL = try XCTUnwrap(URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=abc"))
        let nestedAuthURL = try XCTUnwrap(URL(string: "https://login.accounts.google.com/signin/v2/identifier"))
        let tokenURL = try XCTUnwrap(URL(string: "https://oauth2.googleapis.com/token"))
        let wikiURL = try XCTUnwrap(URL(string: "https://wiki.sourcebottle.dev/apps/feedback-inbox"))
        let googleSearchURL = try XCTUnwrap(URL(string: "https://www.google.com/search?q=hermes"))

        XCTAssertTrue(WikiWebViewModel.shouldOpenExternally(authURL))
        XCTAssertTrue(WikiWebViewModel.shouldOpenExternally(nestedAuthURL))
        XCTAssertTrue(WikiWebViewModel.shouldOpenExternally(tokenURL))
        XCTAssertFalse(WikiWebViewModel.shouldOpenExternally(wikiURL))
        XCTAssertFalse(WikiWebViewModel.shouldOpenExternally(googleSearchURL))
    }

    private func extractFirstURL(from markdown: String) throws -> URL {
        try XCTUnwrap(extractURLs(from: markdown).first)
    }

    private func extractURLs(from markdown: String) throws -> [URL] {
        let pattern = #"\]\(([^)]+)\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return regex.matches(in: markdown, range: range).compactMap { match in
            guard let urlRange = Range(match.range(at: 1), in: markdown) else { return nil }
            return URL(string: String(markdown[urlRange]))
        }
    }
}
