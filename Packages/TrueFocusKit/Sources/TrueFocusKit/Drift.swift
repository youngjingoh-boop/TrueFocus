import Foundation

// Drift guard: notices when what you're doing on the Mac stops matching the task you said
// you'd do, and helps you back. The rules live here so they can be tested on Linux; the Mac
// app feeds in what's in front (app, window title, browser tab) and shows the nudges.

/// What a task looks like when you're actually doing it. Written in a few seconds when the
/// task starts: where it happens, what "done" means, the first move.
public struct TaskContract: Codable, Equatable, Sendable {
    public var taskID: UUID
    public var taskTitle: String
    /// Apps the task happens in: bundle IDs or app names ("com.figma.Desktop", "Notion").
    public var apps: [String]
    /// Sites the task happens on, as hosts ("docs.google.com", "reddit.com").
    public var sites: [String]
    /// Topic words beyond the title ("ScaleMaster", "channels", "마케팅").
    public var keywords: [String]
    public var doneWhen: String?
    public var firstMove: String?
    public var updatedAt: Date
    /// When the start question was put for this task. Set when it's shown, so skipping it (or
    /// closing it) is remembered across relaunches and the same task isn't asked again.
    public var askedAt: Date?

    public init(taskID: UUID, taskTitle: String, apps: [String] = [], sites: [String] = [],
                keywords: [String] = [], doneWhen: String? = nil, firstMove: String? = nil,
                updatedAt: Date = Date(), askedAt: Date? = nil) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.apps = apps
        self.sites = sites
        self.keywords = keywords
        self.doneWhen = doneWhen
        self.firstMove = firstMove
        self.updatedAt = updatedAt
        self.askedAt = askedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try c.decode(UUID.self, forKey: .taskID)
        taskTitle = try c.decodeIfPresent(String.self, forKey: .taskTitle) ?? ""
        apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
        sites = try c.decodeIfPresent([String].self, forKey: .sites) ?? []
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        doneWhen = try c.decodeIfPresent(String.self, forKey: .doneWhen)
        firstMove = try c.decodeIfPresent(String.self, forKey: .firstMove)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        askedAt = try c.decodeIfPresent(Date.self, forKey: .askedAt)
    }

    /// True once you've said where the task happens. Without it, only the title's words count.
    public var hasWorkspace: Bool { !apps.isEmpty || !sites.isEmpty }

    /// Ask "where does it happen?" only once per task: not after a skip, not after a relaunch.
    public var needsStartQuestion: Bool { !hasWorkspace && askedAt == nil }

    /// Words that mark a window or page as part of this task.
    public var topicWords: [String] {
        var seen = Set<String>()
        var words: [String] = []
        let sources = [taskTitle, firstMove ?? "", doneWhen ?? ""] + keywords
        for word in sources.flatMap(TopicWords.extract) where seen.insert(word).inserted {
            words.append(word)
        }
        return words
    }

    /// "This is part of the task": remember the app or site.
    public mutating func include(_ sample: ActivitySample) {
        if let host = sample.host.flatMap(Blocklist.normalizedSite) {
            if !sites.contains(host) { sites.append(host) }
        } else if let app = sample.appBundleID ?? sample.appName, !app.isEmpty,
                  !DriftClassifier.browsers.contains(app) {
            if !apps.contains(where: { $0.caseInsensitiveCompare(app) == .orderedSame }) { apps.append(app) }
        }
        updatedAt = Date()
    }
}

/// One look at what's in front: the app and its window, or the browser tab.
public struct ActivitySample: Equatable, Sendable {
    public var appBundleID: String?
    public var appName: String?
    public var windowTitle: String?
    /// Browser only: the tab's host and title.
    public var host: String?
    public var pageTitle: String?

    public init(appBundleID: String? = nil, appName: String? = nil, windowTitle: String? = nil,
                host: String? = nil, pageTitle: String? = nil) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.host = host
        self.pageTitle = pageTitle
    }

    public var isBrowserTab: Bool { host != nil }

    /// What a person would call it: "reddit.com", "Xcode".
    public var label: String {
        if let host = host.flatMap(Blocklist.normalizedSite) { return host }
        return appName ?? appBundleID ?? "Something else"
    }

    /// The words to match against the task: page title, window title, host.
    public var text: String {
        [pageTitle, windowTitle, host].compactMap { $0 }.joined(separator: " ")
    }

    /// Stable key for caching a judgement.
    public var cacheKey: String {
        [appBundleID ?? appName ?? "", host ?? "", pageTitle ?? windowTitle ?? ""].joined(separator: "|")
    }
}

public enum DriftVerdict: String, Codable, Sendable {
    /// Matches the task.
    case onTask
    /// Utilities that belong to no task: Finder, Calendar, music, a password manager.
    case neutral
    /// Clearly something else: a feed, or an app or site the task doesn't use.
    case offTask
    /// Can't tell from the rules. Counted as drift after a longer wait, or settled by the model.
    case unsure
}

public enum TopicWords {
    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "from", "into", "onto", "about", "this", "that", "these", "those",
        "your", "you", "our", "out", "get", "got", "make", "made", "work", "working", "task", "tasks",
        "session", "new", "more", "some", "any", "all", "can", "will", "just", "then", "than", "them",
        "they", "their", "have", "has", "had", "are", "was", "were", "been", "being", "not", "but",
        "how", "what", "when", "where", "who", "why", "which", "myself", "people", "thing", "things",
        "start", "finish", "done", "today", "tomorrow", "week", "google", "search", "home", "page",
        "untitled", "document", "tab", "window", "app", "www", "com", "http", "https",
    ]

    /// Korean particles and the "-하기" verb ending. A task written as "마케팅을 정리하기" should
    /// still match a window titled "마케팅 채널", so they come off the end of a Hangul word.
    private static let hangulEndings = ["에서", "으로", "에게", "까지", "부터", "하기", "을", "를", "은", "는", "이", "가", "의", "에", "로", "와", "과", "도"]

    /// Lower-cased content words: Latin words of 3+ letters, other scripts (Korean, Japanese,
    /// Chinese…) of 2+ characters, without common filler words. Korean words lose a trailing
    /// particle when at least two characters remain.
    public static func extract(_ text: String) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted
        return text.lowercased()
            .precomposedStringWithCanonicalMapping
            .components(separatedBy: separators)
            .map(stripHangulEnding)
            .filter { word in
                guard !word.isEmpty, !stopwords.contains(word), !word.allSatisfy(\.isNumber) else { return false }
                let latin = word.unicodeScalars.allSatisfy { $0.isASCII }
                return word.count >= (latin ? 3 : 2)
            }
    }

    private static func stripHangulEnding(_ word: String) -> String {
        guard let last = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return word }
        for ending in hangulEndings where word.hasSuffix(ending) && word.count - ending.count >= 2 {
            return String(word.dropLast(ending.count))
        }
        return word
    }

    /// True when any topic word appears in the text (substring, so Korean particles and plurals still match).
    public static func overlaps(_ words: [String], with text: String) -> Bool {
        // Window titles from file names often arrive decomposed (NFD); compare composed forms.
        let haystack = text.lowercased().precomposedStringWithCanonicalMapping
        return words.contains { haystack.contains($0) }
    }
}

public enum DriftClassifier {
    /// Utilities you pass through on the way to anything.
    public static let neutralApps: Set<String> = [
        "com.apple.finder", "com.apple.systempreferences", "com.apple.iCal", "com.apple.Music",
        "com.spotify.client", "com.apple.ActivityMonitor", "com.1password.1password",
        "com.agilebits.onepassword7", "com.apple.keychainaccess", "com.apple.Passwords",
        "com.apple.Spotlight", "com.raycast.macos", "com.runningwithcrayons.Alfred",
        "com.apple.ScreenContinuity", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.dock", "com.apple.loginwindow", "com.apple.SecurityAgent",
        // Calls: you can't leave a meeting for the task, so it neither counts nor nudges.
        "us.zoom.xos", "com.apple.FaceTime", "com.cisco.webexmeetingsapp",
    ]

    /// Mail and chat. Undeclared, they're "unsure" rather than drift: a quick reply never
    /// nudges, a long stay does after `DriftConfig.unsureSeconds` (or the on-device model
    /// decides from the title). Declaring one in the start contract makes it on-task.
    public static let communicationApps: Set<String> = [
        "com.apple.mail", "com.apple.MobileSMS", "com.tinyspeck.slackmacgap", "com.microsoft.teams2",
        "com.microsoft.teams", "com.microsoft.Outlook", "com.readdle.smartemail-Mac", "com.superhuman.electron",
        "com.kakao.KakaoTalkMac", "jp.naver.line.mac", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram",
        "com.tdesktop.Telegram", "com.hnc.Discord", "com.facebook.archon", "com.spark.desktop",
    ]

    /// The same for webmail and chat in a tab.
    public static let communicationSites: [String] = [
        "mail.google.com", "outlook.office.com", "outlook.live.com", "app.slack.com", "teams.microsoft.com",
        "web.whatsapp.com", "web.telegram.org", "messenger.com", "discord.com", "mail.naver.com",
        "meet.google.com", "zoom.us",
    ]

    /// Feed names that show up in a browser's window title ("… - YouTube") when the extension
    /// hasn't reported the tab.
    static let feedTitleNames = ["youtube", "instagram", "facebook", "reddit", "tiktok", "twitch", "pinterest", "netflix"]

    /// Browsers: their tab, not the app, decides.
    public static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "company.thebrowser.dia", "org.mozilla.firefox",
        "com.operasoftware.Opera", "com.google.Chrome.canary",
    ]

    public static func classify(_ sample: ActivitySample, contract: TaskContract) -> DriftVerdict {
        let words = contract.topicWords

        if let rawHost = sample.host, let host = Blocklist.normalizedSite(rawHost) {
            if contract.sites.contains(where: { Blocklist.normalizedSite($0).map { host == $0 || host.hasSuffix("." + $0) } ?? false }) {
                return .onTask
            }
            if TopicWords.overlaps(words, with: sample.text) { return .onTask }
            if Blocklist.feedSite(forHost: host) != nil { return .offTask }
            if communicationSites.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .unsure }
            return contract.hasWorkspace ? .offTask : .unsure
        }

        let id = sample.appBundleID ?? ""
        let name = sample.appName ?? ""
        let isBrowser = browsers.contains(id)
        // A browser never counts as a whole: which tab is open decides.
        if !isBrowser,
           contract.apps.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame || $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return .onTask
        }
        if neutralApps.contains(id) { return .neutral }
        if TopicWords.overlaps(words, with: sample.text) { return .onTask }
        if Blocklist.macFeedApps[id] != nil { return .offTask }
        if isBrowser {
            // No tab report (extension missing, not connected, or the report went stale): the
            // site is unknown, so a declared site can't be recognised. Only an obvious feed in
            // the window title counts as drift; anything else waits for the longer "unsure" clock.
            let title = (sample.windowTitle ?? "").lowercased()
            return feedTitleNames.contains(where: { title.contains($0) }) ? .offTask : .unsure
        }
        if communicationApps.contains(id) { return .unsure }
        return contract.hasWorkspace ? .offTask : .unsure
    }
}

/// How patient the guard is. Defaults follow the research: give focus a few minutes to
/// arrive, then catch sustained drift, not quick look-ups. Every timing the guard uses lives
/// here (plus `BrowserTabReport.freshSeconds`), so tuning is a one-line change.
public struct DriftConfig: Codable, Equatable, Sendable {
    /// After a task starts, only clear drift (a feed, an app or site outside the workspace) counts.
    public var warmUpSeconds: TimeInterval
    /// Continuous time somewhere clearly off-task before a nudge.
    public var offTaskSeconds: TimeInterval
    /// Continuous time somewhere the rules can't place before a nudge.
    public var unsureSeconds: TimeInterval
    /// Minimum gap between nudges while you stay off.
    public var renudgeSeconds: TimeInterval
    /// How often the Mac looks at what's in front.
    public var sampleSeconds: TimeInterval
    /// A gap between samples longer than this means the Mac slept or wasn't looking: it counts
    /// at most this long in the tally, and the Mac app treats it as time away.
    public var maxGapSeconds: TimeInterval
    /// No keyboard or mouse for this long: you're away, so nothing is sampled.
    public var idleSeconds: TimeInterval

    public init(warmUpSeconds: TimeInterval = 5 * 60, offTaskSeconds: TimeInterval = 90,
                unsureSeconds: TimeInterval = 4 * 60, renudgeSeconds: TimeInterval = 4 * 60,
                sampleSeconds: TimeInterval = 3, maxGapSeconds: TimeInterval = 60,
                idleSeconds: TimeInterval = 5 * 60) {
        self.warmUpSeconds = warmUpSeconds
        self.offTaskSeconds = offTaskSeconds
        self.unsureSeconds = unsureSeconds
        self.renudgeSeconds = renudgeSeconds
        self.sampleSeconds = sampleSeconds
        self.maxGapSeconds = maxGapSeconds
        self.idleSeconds = idleSeconds
    }

    public static let standard = DriftConfig()
}

/// "You've been on X for N minutes, and X isn't your task."
public struct DriftNudge: Equatable, Sendable {
    public var taskTitle: String
    public var label: String
    public var minutes: Int
    public var verdict: DriftVerdict
    public var sample: ActivitySample
    public var lastOnTask: ActivitySample?
}

/// Today's honest ledger for one task: time on it, time drifted, and where the drift went.
public struct DriftTally: Codable, Equatable, Sendable {
    public var taskTitle: String
    public var onTask: TimeInterval = 0
    public var offTask: TimeInterval = 0
    public var neutral: TimeInterval = 0
    /// Where drift went, by label ("reddit.com", "Xcode"), in seconds.
    public var drift: [String: TimeInterval] = [:]

    public init(taskTitle: String) {
        self.taskTitle = taskTitle
    }

    public var topDrift: (label: String, seconds: TimeInterval)? {
        drift.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
}

/// The pure state machine. Feed it a sample with its verdict every few seconds; it keeps the
/// tally and says when a nudge is due.
public struct DriftMonitor: Sendable {
    public var config: DriftConfig
    public private(set) var taskID: UUID?
    public private(set) var taskTitle = ""
    public private(set) var startedAt: Date?
    public private(set) var tally: DriftTally?
    public private(set) var lastOnTask: ActivitySample?

    private var lastSample: ActivitySample?
    private var lastVerdict: DriftVerdict?
    private var lastAt: Date?
    /// When the current stretch of drift began (nil while on-task or neutral).
    private var driftSince: Date?
    private var driftKind: DriftVerdict?
    private var lastNudgeAt: Date?

    public init(config: DriftConfig = .standard) {
        self.config = config
    }

    /// A new task (or the same task picked up again) begins.
    public mutating func begin(taskID: UUID, title: String, at: Date, tally: DriftTally? = nil) {
        self.taskID = taskID
        taskTitle = title
        startedAt = at
        self.tally = tally ?? DriftTally(taskTitle: title)
        lastSample = nil
        lastVerdict = nil
        lastAt = nil
        driftSince = nil
        driftKind = nil
        lastNudgeAt = nil
        lastOnTask = nil
    }

    /// Stop watching (rest, pause, idle). Returns the tally to keep.
    public mutating func end(at: Date) -> DriftTally? {
        accrue(until: at)
        let result = tally
        taskID = nil
        startedAt = nil
        tally = nil
        lastSample = nil
        lastVerdict = nil
        lastAt = nil
        driftSince = nil
        driftKind = nil
        return result
    }

    /// A new day began mid-task (days roll over at 4 am): today's tally starts from zero.
    public mutating func startNewTally() {
        guard tally != nil else { return }
        tally = DriftTally(taskTitle: taskTitle)
    }

    /// You stepped away (no input for a while, or the Mac slept): the drift clock stops, the
    /// time away isn't counted, and sampling picks up fresh when you're back.
    public mutating func away(at: Date) {
        accrue(until: at)
        lastSample = nil
        lastVerdict = nil
        lastAt = nil
        driftSince = nil
        driftKind = nil
    }

    /// Back on track: forget the current stretch of drift.
    public mutating func acknowledge(at: Date) {
        driftSince = nil
        driftKind = nil
        lastNudgeAt = at
    }

    public mutating func observe(_ sample: ActivitySample, verdict: DriftVerdict, at: Date) -> DriftNudge? {
        guard taskID != nil, let startedAt else { return nil }
        accrue(until: at)
        lastSample = sample
        lastVerdict = verdict
        lastAt = at

        switch verdict {
        case .onTask:
            lastOnTask = sample
            driftSince = nil
            driftKind = nil
            return nil
        case .neutral:
            // Passing through a utility neither starts nor ends drift.
            return nil
        case .offTask, .unsure:
            if driftSince == nil || driftKind != verdict {
                // Off → unsure (or back) keeps the clock running from the first slip.
                if driftSince == nil { driftSince = at }
                driftKind = verdict
            }
        }

        guard let since = driftSince else { return nil }
        let inWarmUp = at.timeIntervalSince(startedAt) < config.warmUpSeconds
        // While focus is still arriving, only clear drift counts, and it needs twice as long.
        if inWarmUp && verdict == .unsure { return nil }
        let needed = (verdict == .offTask ? config.offTaskSeconds : config.unsureSeconds) * (inWarmUp ? 2 : 1)
        let away = at.timeIntervalSince(since)
        guard away >= needed else { return nil }
        if let last = lastNudgeAt, at.timeIntervalSince(last) < config.renudgeSeconds { return nil }
        lastNudgeAt = at
        return DriftNudge(taskTitle: taskTitle, label: sample.label, minutes: max(1, Int((away / 60).rounded())),
                          verdict: verdict, sample: sample, lastOnTask: lastOnTask)
    }

    /// Adds the time since the last sample to the tally under that sample's verdict.
    private mutating func accrue(until at: Date) {
        guard var tally, let lastAt, let lastVerdict, let lastSample else { return }
        // Gaps longer than a minute mean the Mac slept or we weren't looking; don't count them.
        let elapsed = min(max(0, at.timeIntervalSince(lastAt)), config.maxGapSeconds)
        switch lastVerdict {
        case .onTask: tally.onTask += elapsed
        case .neutral: tally.neutral += elapsed
        case .offTask, .unsure:
            tally.offTask += elapsed
            tally.drift[lastSample.label, default: 0] += elapsed
        }
        self.tally = tally
        self.lastAt = at
    }
}

/// Contracts and today's tallies, kept in the App Group on this Mac. Never synced.
public struct DriftBook: Codable, Equatable, Sendable {
    public var contracts: [UUID: TaskContract] = [:]
    /// Day key ("2026-10-19") → task → tally.
    public var day: String = ""
    public var tallies: [UUID: DriftTally] = [:]

    public init() {}

    public static let key = "tf.drift.v1"

    public mutating func save(_ contract: TaskContract) {
        contracts[contract.taskID] = contract
        if contracts.count > 300 {
            let oldest = contracts.values.sorted { $0.updatedAt < $1.updatedAt }.prefix(contracts.count - 300)
            for contract in oldest { contracts[contract.taskID] = nil }
        }
    }

    /// Drops tallies from an earlier day, so nothing about yesterday stays on disk even on a day
    /// with no focus. Returns true when something changed.
    @discardableResult
    public mutating func prune(dayKey: String) -> Bool {
        guard day != dayKey else { return false }
        let changed = !tallies.isEmpty
        day = dayKey
        tallies = [:]
        return changed
    }

    /// Today's tallies; yesterday's are dropped.
    public mutating func record(_ tally: DriftTally, for taskID: UUID, dayKey: String) {
        if day != dayKey {
            day = dayKey
            tallies = [:]
        }
        tallies[taskID] = tally
    }

    public func tally(for taskID: UUID, dayKey: String) -> DriftTally? {
        day == dayKey ? tallies[taskID] : nil
    }

    /// All of today: on-task and drifted seconds, and the biggest single drift.
    public func today(dayKey: String) -> (onTask: TimeInterval, offTask: TimeInterval, top: (label: String, seconds: TimeInterval)?) {
        guard day == dayKey else { return (0, 0, nil) }
        var drift: [String: TimeInterval] = [:]
        var on: TimeInterval = 0
        var off: TimeInterval = 0
        for tally in tallies.values {
            on += tally.onTask
            off += tally.offTask
            for (label, seconds) in tally.drift { drift[label, default: 0] += seconds }
        }
        return (on, off, drift.max { $0.value < $1.value }.map { ($0.key, $0.value) })
    }
}

/// The active browser tab, as the TruFocus extension reports it while a task runs.
/// Safari writes it to the App Group; Chrome-family browsers post it to the Mac bridge.
public struct BrowserTabReport: Codable, Equatable, Sendable {
    public static let key = "tf.activity.tab.v1"
    /// The extension re-sends the active tab every 30 seconds while a task runs; a report
    /// younger than this still holds.
    public static let freshSeconds: TimeInterval = 45

    public var host: String
    public var title: String
    public var at: Date

    public init(host: String, title: String, at: Date = Date()) {
        self.host = host
        self.title = title
        self.at = at
    }

    /// Cleans what a browser sent: a real host, a bounded title. Nil if there's no usable host.
    public static func make(host: String?, title: String?, at: Date = Date()) -> BrowserTabReport? {
        guard let host = host.flatMap(Blocklist.normalizedSite) else { return nil }
        let cleanTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return BrowserTabReport(host: host, title: String(cleanTitle.prefix(200)), at: at)
    }

    /// The tab to trust for the browser in front. Safari reports through the App Group, the
    /// Chrome family through the bridge, so one browser's tab never stands in for another's.
    /// An old report still holds while the window title shows its page title.
    public static func current(forBrowser bundleID: String, windowTitle: String?,
                               bridge: BrowserTabReport?, safari: BrowserTabReport?,
                               now: Date = Date()) -> BrowserTabReport? {
        guard DriftClassifier.browsers.contains(bundleID) else { return nil }
        guard let tab = bundleID == "com.apple.Safari" ? safari : bridge else { return nil }
        let age = now.timeIntervalSince(tab.at)
        if age >= 0, age < freshSeconds { return tab }
        guard let windowTitle, !tab.title.isEmpty else { return nil }
        return windowTitle.contains(tab.title) ? tab : nil
    }
}
