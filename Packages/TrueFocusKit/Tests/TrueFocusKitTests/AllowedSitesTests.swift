import XCTest
@testable import TrueFocusKit

final class AllowedSitesTests: XCTestCase {
    func testSiteNamesNormalise() {
        XCTAssertEqual(Blocklist.normalizedSite("https://www.LinkedIn.com/feed/?x=1"), "linkedin.com")
        XCTAssertEqual(Blocklist.normalizedSite("  notion.so "), "notion.so")
        XCTAssertEqual(Blocklist.normalizedSite("app.slack.com:443"), "app.slack.com")
        XCTAssertNil(Blocklist.normalizedSite("localhost"))
        XCTAssertNil(Blocklist.normalizedSite("two words.com"))
        XCTAssertNil(Blocklist.normalizedSite("a..b.com"))
    }

    func testAllowedCoversSubdomainsButNotLookalikes() {
        XCTAssertTrue(Blocklist.isAllowed(host: "old.reddit.com", allowedSites: ["reddit.com"]))
        XCTAssertTrue(Blocklist.isAllowed(host: "REDDIT.com", allowedSites: ["reddit.com"]))
        XCTAssertFalse(Blocklist.isAllowed(host: "notreddit.com", allowedSites: ["reddit.com"]))
    }

    func testLinkedInWorkPagesAreSafeAndOnlyTheFeedScrolls() throws {
        let site = try XCTUnwrap(Blocklist.feedSite(forHost: "www.linkedin.com"))
        for path in ["/messaging/thread/1", "/in/someone/", "/search/results/people/", "/sales/home",
                     "/campaignmanager/accounts/1", "/feed/update/urn:li:activity:1/", "/mynetwork/"] {
            XCTAssertTrue(site.isSafe(path: path), path)
        }
        XCTAssertTrue(Blocklist.isLinkedInFeed(path: "/feed/"))
        XCTAssertTrue(Blocklist.isLinkedInFeed(path: "/"))
        XCTAssertFalse(Blocklist.isLinkedInFeed(path: "/feed/update/urn:li:activity:1/"))
        XCTAssertTrue(site.isShortForm(path: "/video/"))
        XCTAssertFalse(site.isShortForm(path: "/videos-tips"))
        XCTAssertNil(Blocklist.feedSite(forHost: "business.linkedin.com"))
    }

    func testFacebookSignInIsSafeAndOnlyFeedAndVideoGo() throws {
        let site = try XCTUnwrap(Blocklist.feedSite(forHost: "www.facebook.com"))
        for path in ["/v19.0/dialog/oauth", "/dialog/oauth", "/login.php", "/checkpoint/1/", "/messages/t/1"] {
            XCTAssertTrue(site.isSafe(path: path), path)
        }
        XCTAssertFalse(site.isSafe(path: "/v19.0/acmebakery"))
        XCTAssertTrue(Blocklist.isFacebookFeed(path: "/"))
        XCTAssertTrue(Blocklist.isFacebookFeed(path: "/home.php"))
        XCTAssertFalse(Blocklist.isFacebookFeed(path: "/groups/123/"))
        XCTAssertTrue(Blocklist.isFacebookVideo(path: "/somepage/videos/1/"))
        XCTAssertTrue(Blocklist.isFacebookVideo(path: "/stories/1/"))
        XCTAssertFalse(Blocklist.isFacebookVideo(path: "/videoshop"))
        XCTAssertTrue(site.isShortForm(path: "/stories/1/"))
        XCTAssertNil(Blocklist.feedSite(forHost: "developers.facebook.com"))
    }

    func testSettingsDefaultsAndOlderSettingsDecode() throws {
        XCTAssertTrue(TFSettings().facebookWorkOnly)
        XCTAssertTrue(TFSettings().linkedInWorkOnly)
        XCTAssertEqual(TFSettings().allowedSites, [])
        let old = try JSONDecoder().decode(TFSettings.self, from: Data(#"{"tone":"calm"}"#.utf8))
        XCTAssertTrue(old.linkedInWorkOnly)
        XCTAssertTrue(old.facebookWorkOnly)
        XCTAssertEqual(old.allowedSites, [])
        var s = TFSettings()
        s.allowedSites = ["notion.so"]
        let round = try JSONDecoder().decode(TFSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round.allowedSites, ["notion.so"])
    }
}
