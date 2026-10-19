import Foundation

/// User settings shared by the app and every extension (through the App Group).
/// Decoding is tolerant: a missing key falls back to its default, so new settings
/// never wipe old ones.
public struct TFSettings: Codable, Equatable, Sendable {
    // Flow
    public var tone: NudgeTone = .savage
    public var restBaseSeconds: Double = 45
    public var adaptiveRest: Bool = true
    /// Start the next task automatically when the micro-rest ends.
    public var autoContinue: Bool = true
    public var thinkNudgeMinutes: Double = 5
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
    /// iPhone: shield button that lets you reply to messages for a couple of minutes.
    public var respondPassMinutes: Int = 2
    public var respondPassesPerDay: Int = 8
    /// Web: Instagram opens straight to your DMs. Feed, reels and explore are gone.
    public var instagramMessagesOnly: Bool = true
    public var hideShortForm: Bool = true
    /// Web: LinkedIn without the feed. The home feed opens Messaging; video is gone; profiles,
    /// search, jobs, Sales Navigator and Campaign Manager stay open, unguarded, even in focus.
    public var linkedInWorkOnly: Bool = true
    /// Web: sites you always allow (host names like "notion.so"). Never blocked, guarded or
    /// cooled down. The adult filter still applies.
    public var allowedSites: [String] = []

    // Mac
    /// Run Shortcuts named below to flip a macOS Focus (which syncs to iPhone) on and off.
    public var macRunFocusShortcuts: Bool = false
    public var macFocusOnShortcut: String = "TrueFocus On"
    public var macFocusOffShortcut: String = "TrueFocus Off"
    public var menuBarShowsTimer: Bool = true
    public var macWatchNativeScrolling: Bool = true
    public var macWatchBrowsers: Bool = true
    public var macBlockedApps: [String] = []

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
        restBaseSeconds = try c.decodeIfPresent(Double.self, forKey: .restBaseSeconds) ?? d.restBaseSeconds
        adaptiveRest = try c.decodeIfPresent(Bool.self, forKey: .adaptiveRest) ?? d.adaptiveRest
        autoContinue = try c.decodeIfPresent(Bool.self, forKey: .autoContinue) ?? d.autoContinue
        thinkNudgeMinutes = try c.decodeIfPresent(Double.self, forKey: .thinkNudgeMinutes) ?? d.thinkNudgeMinutes
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
        allowedSites = try c.decodeIfPresent([String].self, forKey: .allowedSites) ?? d.allowedSites
        macRunFocusShortcuts = try c.decodeIfPresent(Bool.self, forKey: .macRunFocusShortcuts) ?? d.macRunFocusShortcuts
        macFocusOnShortcut = try c.decodeIfPresent(String.self, forKey: .macFocusOnShortcut) ?? d.macFocusOnShortcut
        macFocusOffShortcut = try c.decodeIfPresent(String.self, forKey: .macFocusOffShortcut) ?? d.macFocusOffShortcut
        menuBarShowsTimer = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowsTimer) ?? d.menuBarShowsTimer
        macWatchNativeScrolling = try c.decodeIfPresent(Bool.self, forKey: .macWatchNativeScrolling) ?? d.macWatchNativeScrolling
        macWatchBrowsers = try c.decodeIfPresent(Bool.self, forKey: .macWatchBrowsers) ?? d.macWatchBrowsers
        macBlockedApps = try c.decodeIfPresent([String].self, forKey: .macBlockedApps) ?? d.macBlockedApps
        adultFilterEnabled = try c.decodeIfPresent(Bool.self, forKey: .adultFilterEnabled) ?? d.adultFilterEnabled
        adultFilterOffRequestedAt = try c.decodeIfPresent(Date.self, forKey: .adultFilterOffRequestedAt)
        adultFilterCoolOffHours = try c.decodeIfPresent(Double.self, forKey: .adultFilterCoolOffHours) ?? d.adultFilterCoolOffHours
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
        respondPassMinutes = min(max(respondPassMinutes, 1), 10)
        respondPassesPerDay = min(max(respondPassesPerDay, 0), 30)
        adultFilterCoolOffHours = min(max(adultFilterCoolOffHours, 1), 168)
    }
}
