import Foundation

/// What TrueFocus blocks, in one place.
///
/// Keep `Extensions/web/core.js` and `macOS/Resources/PermanentShield/adult-domains.txt`
/// in step with these lists (a unit test checks the text file).
public enum Blocklist {
    /// A site whose feed is engineered for endless scrolling.
    public struct FeedSite: Equatable, Sendable {
        public var name: String
        /// Host suffixes, e.g. "instagram.com" matches "www.instagram.com".
        public var hosts: [String]
        /// Path prefixes that are pure short-form video. Always blocked.
        public var shortFormPaths: [String]
        /// Where "respond mode" lands you: messages only, no feed.
        public var respondPath: String?
        /// Paths that are safe to use without the scroll guard (messages, settings, upload).
        public var safePaths: [String]
        /// The whole site is short-form (TikTok): everything except `safePaths` is blocked.
        public var allShortForm: Bool
        /// Subdomains that are work tools, not the feed (Ads Manager, Business Suite), or link
        /// shims that only pass a link on (l.instagram.com). Never guarded, shielded or cooled
        /// down, even while the feed itself is blocked.
        public var workHosts: [String]

        public init(name: String, hosts: [String], shortFormPaths: [String] = [],
                    respondPath: String? = nil, safePaths: [String] = [], allShortForm: Bool = false,
                    workHosts: [String] = []) {
            self.name = name
            self.hosts = hosts
            self.shortFormPaths = shortFormPaths
            self.respondPath = respondPath
            self.safePaths = safePaths
            self.allShortForm = allShortForm
            self.workHosts = workHosts
        }

        public func matches(host: String) -> Bool {
            let h = host.lowercased()
            if workHosts.contains(where: { Self.host(h, isOrIsUnder: $0) }) { return false }
            return hosts.contains { Self.host(h, isOrIsUnder: $0) }
        }

        private static func host(_ host: String, isOrIsUnder suffix: String) -> Bool {
            host == suffix || host.hasSuffix("." + suffix)
        }

        public func isShortForm(path: String) -> Bool {
            if allShortForm { return !isSafe(path: path) }
            return shortFormPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
        }

        public func isSafe(path: String) -> Bool {
            // Facebook's dialogs also live under a Graph API version: /v19.0/dialog/oauth.
            var p = path
            if name == "Facebook", let version = p.range(of: #"^/v[0-9]+(\.[0-9]+)?(?=/)"#, options: .regularExpression) {
                p.removeSubrange(version)
            }
            return safePaths.contains { p.hasPrefix($0) }
        }
    }

    public static let feedSites: [FeedSite] = [
        FeedSite(name: "Instagram", hosts: ["instagram.com"],
                 shortFormPaths: ["/reels", "/explore"],
                 respondPath: "/direct/inbox/", safePaths: ["/direct", "/accounts", "/create"],
                 workHosts: ["business.instagram.com", "accountscenter.instagram.com", "help.instagram.com",
                             "l.instagram.com"]),
        // youtube.com/upload opens in Studio, so Studio is work too.
        FeedSite(name: "YouTube", hosts: ["youtube.com", "youtu.be"],
                 shortFormPaths: ["/shorts"], safePaths: ["/upload", "/account"],
                 workHosts: ["studio.youtube.com"]),
        // All short-form, except messages, posting, sign-in ("Log in with TikTok") and the
        // ads, business, developer and seller tools.
        FeedSite(name: "TikTok", hosts: ["tiktok.com"],
                 respondPath: "/messages",
                 safePaths: ["/messages", "/upload", "/tiktokstudio", "/login", "/setting", "/auth", "/v2/auth"],
                 allShortForm: true,
                 workHosts: ["ads.tiktok.com", "business.tiktok.com", "developers.tiktok.com", "seller-us.tiktok.com"]),
        // Meta's business tools stay open for running ads: Business Suite and Business Manager
        // (business.facebook.com), Ads Manager, Events and Commerce Manager, the Ad Library.
        // Sign-in and app-login dialogs (Graph API Explorer, "Log in with Facebook") are safe too.
        FeedSite(name: "Facebook", hosts: ["facebook.com"],
                 shortFormPaths: ["/reels", "/watch", "/stories"],
                 respondPath: "/messages/",
                 safePaths: ["/messages", "/settings", "/adsmanager", "/ads/", "/business", "/events_manager",
                             "/commerce_manager", "/billing_hub", "/ad_center", "/help", "/dialog", "/login", "/oauth",
                             "/connect", "/checkpoint", "/recover", "/two_step_verification", "/auth", "/device",
                             "/privacy", "/security", "/policies", "/legal"],
                 workHosts: ["business.facebook.com", "adsmanager.facebook.com", "developers.facebook.com",
                             "accountscenter.facebook.com", "l.facebook.com", "lm.facebook.com"]),
        FeedSite(name: "X", hosts: ["x.com", "twitter.com"],
                 respondPath: "/messages", safePaths: ["/messages", "/compose", "/settings"]),
        FeedSite(name: "Threads", hosts: ["threads.net", "threads.com"]),
        FeedSite(name: "Reddit", hosts: ["reddit.com"], safePaths: ["/message", "/settings", "/submit"]),
        // LinkedIn is a work tool with a feed bolted on. Everything you work in stays open —
        // messaging, profiles, search, jobs, Sales Navigator, Recruiter, Campaign Manager, a
        // single post someone sent you. Only the home feed and the video feed are the scroll.
        FeedSite(name: "LinkedIn", hosts: ["linkedin.com"],
                 shortFormPaths: ["/video", "/feed/videos"],
                 respondPath: "/messaging/",
                 safePaths: ["/messaging", "/in/", "/jobs", "/company", "/school", "/search", "/mynetwork",
                             "/notifications", "/sales", "/talent", "/recruiter", "/campaignmanager", "/ad/",
                             "/analytics", "/dashboard", "/post/", "/feed/update/", "/posts/", "/pulse/",
                             "/newsletters", "/events", "/groups", "/learning", "/premium", "/settings",
                             "/psettings", "/mypreferences", "/help", "/my-items", "/services", "/verify",
                             "/checkpoint", "/login", "/uas", "/signup", "/authwall", "/safety/go", "/redir/"],
                 workHosts: ["business.linkedin.com", "developer.linkedin.com", "learn.linkedin.com"]),
        FeedSite(name: "Snapchat", hosts: ["snapchat.com"], shortFormPaths: ["/spotlight"]),
        FeedSite(name: "Pinterest", hosts: ["pinterest.com"]),
        FeedSite(name: "Twitch", hosts: ["twitch.tv"]),
    ]

    public static func feedSite(forHost host: String) -> FeedSite? {
        feedSites.first { $0.matches(host: host) }
    }

    /// LinkedIn's scroll: the home feed. Everything else on LinkedIn is work (see `feedSites`).
    public static func isLinkedInFeed(path: String) -> Bool {
        path.isEmpty || path == "/" || path == "/feed" || path == "/feed/"
    }

    /// Facebook's scroll: the News Feed and the groups feed. In work-only mode they open Messenger.
    public static func isFacebookFeed(path: String) -> Bool {
        ["", "/", "/home.php", "/groups", "/groups/", "/groups/feed", "/groups/feed/"].contains(path)
    }

    /// Facebook video in work-only mode: Watch, Reels, Stories, Gaming and any page's videos.
    public static func isFacebookVideo(path: String) -> Bool {
        path.range(of: #"(^|/)(watch|reel|reels|stories|videos|gaming)(/|$)"#, options: .regularExpression) != nil
    }

    /// "https://www.LinkedIn.com/feed/" → "linkedin.com". What you type into "Always allowed".
    /// Nil for anything that isn't a plausible host.
    public static func normalizedSite(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        if let cut = text.firstIndex(where: { "/?#:".contains($0) }) { text = String(text[..<cut]) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        guard text.contains("."), text.count <= 253,
              text.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !text.split(separator: ".", omittingEmptySubsequences: false).contains(where: \.isEmpty) else { return nil }
        return text
    }

    /// The host is one you always allow (the site itself or any of its subdomains).
    public static func isAllowed(host: String, allowedSites: [String]) -> Bool {
        let h = host.lowercased()
        return allowedSites.contains { site in h == site || h.hasSuffix("." + site) }
    }

    /// Native Mac apps (iPad apps on Apple silicon included) that are feeds.
    public static let macFeedApps: [String: String] = [
        "com.burbn.instagram": "Instagram",
        "com.zhiliaoapp.musically": "TikTok",
        "com.google.ios.youtube": "YouTube",
        "com.atebits.Tweetie2": "X",
        "com.burbn.barcelona": "Threads",
        "com.facebook.Facebook": "Facebook",
        "com.reddit.Reddit": "Reddit",
        "com.toyopagroup.picaboo": "Snapchat",
        "com.netflix.Netflix": "Netflix",
    ]

    /// Feed sites that have a work mode: the site stays open, even in focus, with only its home
    /// feed hidden, and scrolling it brings a "working or scrolling?" check instead of a boot-out.
    /// LinkedIn has its own switch (`linkedInWorkOnly`); Facebook's stricter `facebookWorkOnly`
    /// (no posts anywhere) applies only while Facebook isn't open for work.
    public static let workPlatforms: [String] = ["YouTube", "Instagram", "X", "Facebook"]

    /// Mac apps shielded during focus: your own list, plus the built-in feed apps you haven't allowed.
    public static func macShieldedApps(custom: [String], allowedFeedApps: [String]) -> Set<String> {
        let allowed = Set(allowedFeedApps)
        return Set(custom).union(macFeedApps.keys.filter { !allowed.contains($0) })
    }

    /// Feed apps and sites you've opened up for work: bundle IDs and platform names. The drift
    /// guard treats these like any other app or site instead of as drift on sight.
    public static func workAccess(_ settings: TFSettings) -> Set<String> {
        Set(settings.macAllowedFeedApps).union(settings.workPlatforms)
    }

    /// Browsers the Mac watcher can read the current tab from.
    public static let scriptableBrowsers: [String: String] = [
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Google Chrome",
        "company.thebrowser.Browser": "Arc",
        "com.brave.Browser": "Brave Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.operasoftware.Opera": "Opera",
        "company.thebrowser.dia": "Dia",
    ]

    /// Substrings that mark adult content anywhere in a hostname.
    public static let adultKeywords: [String] = [
        "porn", "xxx", "hentai", "xvideo", "xnxx", "xhamster", "nsfw", "onlyfans", "camgirl",
        "redtube", "youporn", "brazzers", "chaturbate", "stripchat", "livejasmin", "rule34",
    ]

    /// Major adult domains. The real wall is the OS-level adult filter (Screen Time
    /// on iPhone and Mac); this list is the second wall in the browser and hosts file.
    public static let adultDomains: [String] = [
        "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "redtube.com", "youporn.com",
        "tube8.com", "spankbang.com", "eporner.com", "onlyfans.com", "fansly.com", "chaturbate.com",
        "stripchat.com", "bongacams.com", "cam4.com", "livejasmin.com", "myfreecams.com",
        "camsoda.com", "brazzers.com", "realitykings.com", "bangbros.com", "naughtyamerica.com",
        "porn.com", "pornhd.com", "hqporner.com", "txxx.com", "hclips.com", "tnaflix.com",
        "empflix.com", "motherless.com", "fapello.com", "rule34.xxx", "rule34.paheal.net",
        "e-hentai.org", "exhentai.org", "nhentai.net", "hanime.tv", "hentaihaven.xxx", "iwara.tv",
        "porntrex.com", "beeg.com", "sunporno.com", "drtuber.com", "nuvid.com", "4tube.com",
        "porntube.com", "fuq.com", "ixxx.com", "thumbzilla.com", "youjizz.com", "keezmovies.com",
        "extremetube.com", "spankwire.com", "slutload.com", "xtube.com", "manyvids.com",
        "clips4sale.com", "erome.com", "thothub.to", "coomer.su", "kemono.su", "simpcity.su",
        "pornpics.com", "imagefap.com", "literotica.com", "sex.com", "adultfriendfinder.com",
        "xxxbunker.com", "pornone.com", "3movs.com", "tubegalore.com", "porngo.com",
        "perfectgirls.net", "ok.xxx", "vjav.com", "javhd.com", "missav.com", "jable.tv",
        "supjav.com", "xhamsterlive.com", "pornhubpremium.com", "modelhub.com", "youporngay.com",
        "xvideos.red", "xnxx.tv", "sxyprn.com", "porndig.com", "pornktube.com", "anysex.com",
        "hdzog.com", "upornia.com", "vxxx.com", "redgifs.com", "scrolller.com", "f95zone.to",
    ]

    /// Subdomains worth listing explicitly in a hosts file (it has no wildcards).
    public static let hostsFileSubdomains: [String] = ["", "www.", "m.", "de.", "fr.", "es.", "it.", "jp.", "rt.", "cn."]

    public static func isAdult(host: String) -> Bool {
        let h = host.lowercased()
        if adultDomains.contains(where: { h == $0 || h.hasSuffix("." + $0) }) { return true }
        return adultKeywords.contains { h.contains($0) }
    }
}
