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
        /// Subdomains that are work tools, not the feed (Ads Manager, Business Suite). Never
        /// guarded, shielded or cooled down, even while the feed itself is blocked.
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
            safePaths.contains { path.hasPrefix($0) }
        }
    }

    public static let feedSites: [FeedSite] = [
        FeedSite(name: "Instagram", hosts: ["instagram.com"],
                 shortFormPaths: ["/reels", "/reel", "/explore"],
                 respondPath: "/direct/inbox/", safePaths: ["/direct", "/accounts", "/create"],
                 workHosts: ["business.instagram.com", "accountscenter.instagram.com", "help.instagram.com"]),
        FeedSite(name: "YouTube", hosts: ["youtube.com", "youtu.be"],
                 shortFormPaths: ["/shorts"], safePaths: ["/upload", "/account"]),
        FeedSite(name: "TikTok", hosts: ["tiktok.com"],
                 respondPath: "/messages", safePaths: ["/messages", "/upload", "/tiktokstudio", "/login", "/setting"],
                 allShortForm: true),
        // Meta's business tools stay open for running ads: Business Suite and Business Manager
        // (business.facebook.com), Ads Manager, Events and Commerce Manager, the Ad Library.
        FeedSite(name: "Facebook", hosts: ["facebook.com"],
                 shortFormPaths: ["/reel", "/reels", "/watch"],
                 respondPath: "/messages/",
                 safePaths: ["/messages", "/settings", "/adsmanager", "/ads/", "/business", "/events_manager",
                             "/commerce_manager", "/billing_hub", "/ad_center", "/help"],
                 workHosts: ["business.facebook.com", "adsmanager.facebook.com", "developers.facebook.com",
                             "accountscenter.facebook.com"]),
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
                             "/checkpoint", "/login", "/uas", "/signup", "/authwall"],
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
