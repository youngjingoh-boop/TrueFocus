import Foundation

/// User settings shared by the app and every extension (through the App Group).
/// Decoding is tolerant: a missing key falls back to its default, so new settings
/// never wipe old ones.
public struct TFSettings: Codable, Equatable, Sendable {
    // Flow
    /// Direct by default. Savage (strong language) is opt-in; saved settings keep their tone.
    public var tone: NudgeTone = .direct
    /// Your own words per reminder moment, in place of the tone's line. Empty by default.
    public var customReminders = CustomReminders()
    public var restBaseSeconds: Double = 45
    public var adaptiveRest: Bool = true
    /// Start the next task automatically when the micro-rest ends.
    public var autoContinue: Bool = true
    public var thinkNudgeMinutes: Double = 5
    /// Check in once after 75 minutes of focus. Off by default so hyperfocus runs uninterrupted.
    public var focusCheckIn: Bool = false
    /// How many tasks you can juggle at once, the current one included.
    public var juggleLimit: Int = 4
    /// Superseded by `juggleLimit` (its old default of 3 left no room to juggle three
    /// tasks beside the current one). Kept so older settings still decode.
    public var maxInPlay: Int = 3

    // Sound
    /// Short studio sounds for done, rest, stuck, back to it, switching and shutting down.
    public var soundEffects: Bool = true
    /// What plays while you focus. Off until you pick something.
    public var focusMusic: FocusMusic = .off
    public var musicVolume: Double = 0.7
    /// A calm river under micro-rests.
    public var restAmbience: Bool = true

    // Doom-scroll guard
    public var doomScroll: DoomScrollConfig = .standard
    /// Shield distracting apps and sites while focus/think is running.
    public var shieldDuringFocus: Bool = true
    /// iPhone: minutes of use in "scroll apps" before you get booted out.
    public var scrollBudgetMinutes: Int = 5
    /// iPhone: how long the boot-out lasts. iOS needs at least 15 minutes.
    public var scrollCooldownMinutes: Int = 15
    /// iPhone: minutes a reply app opens for from its shield's "Post or reply" button —
    /// long enough to post or answer DMs. A notice comes a minute before it closes.
    public var respondPassMinutes: Int = 5
    public var respondPassesPerDay: Int = 8
    /// Web: Instagram opens straight to your DMs. Feed, reels and explore are gone.
    public var instagramMessagesOnly: Bool = true
    public var hideShortForm: Bool = true
    /// Web: LinkedIn without the feed. The home feed opens Messaging; video is gone; profiles,
    /// search, jobs, Sales Navigator and Campaign Manager stay open, unguarded, even in focus.
    public var linkedInWorkOnly: Bool = true
    /// Web: Facebook without the feed. The News Feed opens Messenger; posts, stories, Reels and
    /// video are gone; pages, groups, events, Marketplace and sign-ins stay open, even in focus.
    public var facebookWorkOnly: Bool = true
    /// Web: platforms you use for work (Blocklist.workPlatforms names, e.g. "YouTube"). The whole
    /// site stays open, even in focus, with its feeds hidden; Shorts and Reels stay gone.
    public var workPlatforms: [String] = []
    /// Web: sites you always allow (host names like "notion.so"). Never blocked, guarded or
    /// cooled down. The adult filter still applies.
    public var allowedSites: [String] = []

    // Mac
    /// Run Shortcuts named below to flip a macOS Focus (which syncs to iPhone) on and off.
    public var macRunFocusShortcuts: Bool = false
    public var macFocusOnShortcut: String = "TruFocus On"
    public var macFocusOffShortcut: String = "TruFocus Off"
    public var menuBarShowsTimer: Bool = true
    public var macWatchNativeScrolling: Bool = true
    public var macWatchBrowsers: Bool = true
    /// Mac: notice when the app or tab in front isn't the task you're on, and nudge you back.
    public var macDriftGuard: Bool = true
    /// Mac: use the on-device model to judge windows and tabs the rules can't place.
    public var macDriftUsesModel: Bool = true
    public var macBlockedApps: [String] = []
    /// Mac: built-in feed apps (Blocklist.macFeedApps bundle IDs) you've allowed. They open during
    /// focus; the doom-scroll watch still boots you out of a binge.
    public var macAllowedFeedApps: [String] = []

    // Adult-content filter. On by default. Turning it off asks you to wait out a
    // cool-off period first, so the decision is never made in a weak moment.
    public var adultFilterEnabled: Bool = true
    /// When a request to turn the filter off was made; it turns off once the cool-off passes.
    public var adultFilterOffRequestedAt: Date? = nil
    public var adultFilterCoolOffHours: Double = 24

    public init() {}

    public static let `default` = TFSettings()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TFSettings()
        tone = try c.decodeIfPresent(NudgeTone.self, forKey: .tone) ?? d.tone
        customReminders = (try? c.decodeIfPresent(CustomReminders.self, forKey: .customReminders)) ?? d.customReminders
        restBaseSeconds = try c.decodeIfPresent(Double.self, forKey: .restBaseSeconds) ?? d.restBaseSeconds
        adaptiveRest = try c.decodeIfPresent(Bool.self, forKey: .adaptiveRest) ?? d.adaptiveRest
        autoContinue = try c.decodeIfPresent(Bool.self, forKey: .autoContinue) ?? d.autoContinue
        thinkNudgeMinutes = try c.decodeIfPresent(Double.self, forKey: .thinkNudgeMinutes) ?? d.thinkNudgeMinutes
        focusCheckIn = try c.decodeIfPresent(Bool.self, forKey: .focusCheckIn) ?? d.focusCheckIn
        maxInPlay = try c.decodeIfPresent(Int.self, forKey: .maxInPlay) ?? d.maxInPlay
        juggleLimit = try c.decodeIfPresent(Int.self, forKey: .juggleLimit) ?? d.juggleLimit
        soundEffects = try c.decodeIfPresent(Bool.self, forKey: .soundEffects) ?? d.soundEffects
        focusMusic = (try? c.decodeIfPresent(FocusMusic.self, forKey: .focusMusic)) ?? d.focusMusic
        musicVolume = try c.decodeIfPresent(Double.self, forKey: .musicVolume) ?? d.musicVolume
        restAmbience = try c.decodeIfPresent(Bool.self, forKey: .restAmbience) ?? d.restAmbience
        doomScroll = try c.decodeIfPresent(DoomScrollConfig.self, forKey: .doomScroll) ?? d.doomScroll
        shieldDuringFocus = try c.decodeIfPresent(Bool.self, forKey: .shieldDuringFocus) ?? d.shieldDuringFocus
        scrollBudgetMinutes = try c.decodeIfPresent(Int.self, forKey: .scrollBudgetMinutes) ?? d.scrollBudgetMinutes
        scrollCooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .scrollCooldownMinutes) ?? d.scrollCooldownMinutes
        respondPassMinutes = try c.decodeIfPresent(Int.self, forKey: .respondPassMinutes) ?? d.respondPassMinutes
        respondPassesPerDay = try c.decodeIfPresent(Int.self, forKey: .respondPassesPerDay) ?? d.respondPassesPerDay
        instagramMessagesOnly = try c.decodeIfPresent(Bool.self, forKey: .instagramMessagesOnly) ?? d.instagramMessagesOnly
        hideShortForm = try c.decodeIfPresent(Bool.self, forKey: .hideShortForm) ?? d.hideShortForm
        linkedInWorkOnly = try c.decodeIfPresent(Bool.self, forKey: .linkedInWorkOnly) ?? d.linkedInWorkOnly
        facebookWorkOnly = try c.decodeIfPresent(Bool.self, forKey: .facebookWorkOnly) ?? d.facebookWorkOnly
        workPlatforms = try c.decodeIfPresent([String].self, forKey: .workPlatforms) ?? d.workPlatforms
        allowedSites = try c.decodeIfPresent([String].self, forKey: .allowedSites) ?? d.allowedSites
        macRunFocusShortcuts = try c.decodeIfPresent(Bool.self, forKey: .macRunFocusShortcuts) ?? d.macRunFocusShortcuts
        macFocusOnShortcut = try c.decodeIfPresent(String.self, forKey: .macFocusOnShortcut) ?? d.macFocusOnShortcut
        macFocusOffShortcut = try c.decodeIfPresent(String.self, forKey: .macFocusOffShortcut) ?? d.macFocusOffShortcut
        menuBarShowsTimer = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowsTimer) ?? d.menuBarShowsTimer
        macWatchNativeScrolling = try c.decodeIfPresent(Bool.self, forKey: .macWatchNativeScrolling) ?? d.macWatchNativeScrolling
        macWatchBrowsers = try c.decodeIfPresent(Bool.self, forKey: .macWatchBrowsers) ?? d.macWatchBrowsers
        macDriftGuard = try c.decodeIfPresent(Bool.self, forKey: .macDriftGuard) ?? d.macDriftGuard
        macDriftUsesModel = try c.decodeIfPresent(Bool.self, forKey: .macDriftUsesModel) ?? d.macDriftUsesModel
        macBlockedApps = try c.decodeIfPresent([String].self, forKey: .macBlockedApps) ?? d.macBlockedApps
        macAllowedFeedApps = try c.decodeIfPresent([String].self, forKey: .macAllowedFeedApps) ?? d.macAllowedFeedApps
        adultFilterEnabled = try c.decodeIfPresent(Bool.self, forKey: .adultFilterEnabled) ?? d.adultFilterEnabled
        adultFilterOffRequestedAt = try c.decodeIfPresent(Date.self, forKey: .adultFilterOffRequestedAt)
        adultFilterCoolOffHours = try c.decodeIfPresent(Double.self, forKey: .adultFilterCoolOffHours) ?? d.adultFilterCoolOffHours
        linkWorkPlatforms()
    }

    /// Opens a feed platform for work, or closes it again, with one switch: the Mac app
    /// (Blocklist.macFeedApps) and the website's work mode go together. `platform` is a name
    /// like "YouTube". Opening Facebook also turns on its work-only website; closing it leaves
    /// that alone, since work-only Facebook is on by default.
    public mutating func setOpenForWork(_ platform: String, _ open: Bool) {
        let apps = Blocklist.macFeedApps.filter { $0.value == platform }.map(\.key)
        macAllowedFeedApps.removeAll { apps.contains($0) }
        workPlatforms.removeAll { $0 == platform }
        guard open else { return }
        macAllowedFeedApps.append(contentsOf: apps.sorted())
        if Blocklist.workPlatforms.contains(platform) { workPlatforms.append(platform) }
        if platform == "Facebook" { facebookWorkOnly = true }
    }

    /// Whether a feed platform is open for work: its Mac app is allowed, or its website is in work mode.
    public func isOpenForWork(_ platform: String) -> Bool {
        workPlatforms.contains(platform)
            || Blocklist.macFeedApps.contains { $0.value == platform && macAllowedFeedApps.contains($0.key) }
    }

    /// Settings saved before the app and the website shared one switch could have one open
    /// and not the other (an allowed YouTube app, a blocked youtube.com). Open both.
    mutating func linkWorkPlatforms() {
        for platform in Blocklist.workPlatforms where isOpenForWork(platform) {
            setOpenForWork(platform, true)
        }
    }

    /// Whether the adult filter should be active at `now`, honouring a pending cool-off.
    public func adultFilterActive(now: Date = Date()) -> Bool {
        guard adultFilterEnabled else { return false }
        guard let requested = adultFilterOffRequestedAt else { return true }
        return now < requested.addingTimeInterval(adultFilterCoolOffHours * 3600)
    }

    /// When a pending turn-off takes effect, if one is pending.
    public var adultFilterOffEffectiveAt: Date? {
        adultFilterOffRequestedAt?.addingTimeInterval(adultFilterCoolOffHours * 3600)
    }

    /// Clamp values to what the platforms can honour.
    public mutating func normalize() {
        restBaseSeconds = min(max(restBaseSeconds, 5), 600)
        thinkNudgeMinutes = min(max(thinkNudgeMinutes, 1), 60)
        maxInPlay = min(max(maxInPlay, 1), 5)
        juggleLimit = min(max(juggleLimit, 1), Juggle.maxLimit)
        musicVolume = min(max(musicVolume, 0), 1)
        scrollBudgetMinutes = min(max(scrollBudgetMinutes, 1), 120)
        scrollCooldownMinutes = min(max(scrollCooldownMinutes, 15), 240)
        respondPassMinutes = min(max(respondPassMinutes, 1), 15)
        respondPassesPerDay = min(max(respondPassesPerDay, 0), 30)
        adultFilterCoolOffHours = min(max(adultFilterCoolOffHours, 1), 168)
        customReminders.normalize()
        linkWorkPlatforms()
    }
}
