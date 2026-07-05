import CoreGraphics
import XCTest
@testable import HermesMobile

final class ChatToolbarHeaderTests: XCTestCase {
    func testSubtitleResolverOmitsWorkspaceAndProfileContext() {
        XCTAssertNil(
            ChatToolbarSubtitleResolver.subtitle(
                workspacePath: "/Users/example/hermes-mobile",
                profileTitle: "Default"
            )
        )

        XCTAssertNil(
            ChatToolbarSubtitleResolver.subtitle(
                workspacePath: nil,
                profileTitle: "Work"
            )
        )
    }

    func testSubtitleOmitsGenericOrBlankContext() {
        XCTAssertNil(ChatToolbarSubtitleResolver.subtitle(workspacePath: nil, profileTitle: "Profile"))
        XCTAssertNil(ChatToolbarSubtitleResolver.subtitle(workspacePath: "   ", profileTitle: "   "))
    }

    func testReferenceDraftIncludesChatID() {
        XCTAssertEqual(
            ChatReferenceDraftBuilder.prompt(for: "session-abc123"),
            "Reference chat ID: session-abc123"
        )
    }

    func testHeaderGradientStartsAtScreenTopAndCoversHeaderBar() {
        let topSafeAreaInset: CGFloat = 59
        let headerBarBottom = topSafeAreaInset + ChatHeaderBackgroundGradientLayout.inlineHeaderBarHeight

        XCTAssertEqual(ChatHeaderBackgroundGradientLayout.screenTopY, 0)
        XCTAssertEqual(
            ChatHeaderBackgroundGradientLayout.headerBarBottomY(topSafeAreaInset: topSafeAreaInset),
            headerBarBottom
        )
        XCTAssertEqual(
            ChatHeaderBackgroundGradientLayout.visibleHeight(topSafeAreaInset: topSafeAreaInset),
            headerBarBottom + ChatHeaderBackgroundGradientLayout.fadeExtensionBelowHeader
        )
    }

    func testHeaderGradientUsesSingleLinearFadeThroughTitlebar() {
        let topSafeAreaInset: CGFloat = 59
        let visibleHeight = ChatHeaderBackgroundGradientLayout.visibleHeight(topSafeAreaInset: topSafeAreaInset)
        let headerBarBottom = ChatHeaderBackgroundGradientLayout.headerBarBottomY(topSafeAreaInset: topSafeAreaInset)

        XCTAssertEqual(visibleHeight - headerBarBottom, ChatHeaderBackgroundGradientLayout.fadeExtensionBelowHeader)
        XCTAssertLessThanOrEqual(ChatHeaderBackgroundGradientLayout.fadeExtensionBelowHeader, 12)
    }

    func testHeaderGradientUsesMinimumHeightForCompactTopInsets() {
        XCTAssertEqual(
            ChatHeaderBackgroundGradientLayout.visibleHeight(topSafeAreaInset: 0),
            ChatHeaderBackgroundGradientLayout.minimumVisibleHeight
        )
        XCTAssertLessThanOrEqual(
            ChatHeaderBackgroundGradientLayout.minimumVisibleHeight,
            ChatHeaderBackgroundGradientLayout.inlineHeaderBarHeight
                + ChatHeaderBackgroundGradientLayout.fadeExtensionBelowHeader
                + 8
        )
    }

    func testHeaderGradientClampsNegativeTopInsets() {
        XCTAssertEqual(
            ChatHeaderBackgroundGradientLayout.headerBarBottomY(topSafeAreaInset: -24),
            ChatHeaderBackgroundGradientLayout.inlineHeaderBarHeight
        )
    }

    func testHeaderGradientCoversHeaderAcrossCommonSafeAreaInsets() {
        let topSafeAreaInsets: [CGFloat] = [0, 24, 47, 59, 102]

        for topSafeAreaInset in topSafeAreaInsets {
            let visibleHeight = ChatHeaderBackgroundGradientLayout.visibleHeight(topSafeAreaInset: topSafeAreaInset)
            let headerBarBottom = ChatHeaderBackgroundGradientLayout.headerBarBottomY(topSafeAreaInset: topSafeAreaInset)

            XCTAssertGreaterThanOrEqual(visibleHeight, headerBarBottom, "visibleHeight for \(topSafeAreaInset)")
        }
    }
}
