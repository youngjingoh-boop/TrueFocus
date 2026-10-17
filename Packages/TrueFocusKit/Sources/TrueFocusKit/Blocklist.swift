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

        public init(name: String, hosts: [String], shortFormPaths: [String] = [],
                    respondPath: String? = nil, safePaths: [String] = [], allShortForm: Bool = false) {
            self.name = name
            self.hosts = hosts
            self.shortFormPaths = shortFormPaths
            self.respondPath = respondPath
            self.safePaths = safePaths
            self.allShortForm = allShortForm
        }

        public func matches(host: String) -> Bool {
            let h = host.lowercased()
            return hosts.contains { h == $0 || h.hasSuffix("." + $0) }
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
                 respondPath: "/direct/inbox/", safePaths: ["/direct", "/accounts", "/create"]),
        FeedSite(name: "YouTube", hosts: ["youtube.com", "youtu.be"],
                 shortFormPaths: ["/shorts"], safePaths: ["/upload", "/account"]),
        FeedSite(name: "TikTok", hosts: ["tiktok.com"],
                 respondPath: "/messages", safePaths: ["/messages", "/upload", "/tiktokstudio", "/login", "/setting"],
                 allShortForm: true),
        FeedSite(name: "Facebook", hosts: ["facebook.com"],
                 shortFormPaths: ["/reel", "/reels", "/watch"],
                 respondPath: "/messages/", safePaths: ["/messages", "/settings"]),
        FeedSite(name: "X", hosts: ["x.com", "twitter.com"],
                 respondPath: "/messages", safePaths: ["/messages", "/compose", "/settings"]),
        FeedSite(name: "Threads", hosts: ["threads.net", "threads.com"]),
        FeedSite(name: "Reddit", hosts: ["reddit.com"], safePaths: ["/message", "/settings", "/submit"]),
        FeedSite(name: "LinkedIn", hosts: ["linkedin.com"],
                 respondPath: "/messaging/", safePaths: ["/messaging", "/in/", "/jobs", "/company"]),
        FeedSite(name: "Snapchat", hosts: ["snapchat.com"], shortFormPaths: ["/spotlight"]),
        FeedSite(name: "Pinterest", hosts: ["pinterest.com"]),
        FeedSite(name: "Twitch", hosts: ["twitch.tv"]),
    ]

    public static func feedSite(forHost host: String) -> FeedSite? {
        feedSites.first { $0.matches(host: host) }
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
