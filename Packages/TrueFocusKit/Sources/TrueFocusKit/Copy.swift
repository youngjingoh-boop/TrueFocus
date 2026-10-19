import Foundation

/// Every sentence TrueFocus says to you, in one place, in three tones.
/// Short. Specific. Always names the task, because the task is the point.
///
/// Each moment can be overridden with your own words (`TFSettings.customReminders`).
/// Build it with `Copy(settings:)` so they apply; `Copy(tone:)` gives the built-in lines only.
public struct Copy: Sendable {
    public struct Line: Equatable, Sendable {
        public var title: String
        public var body: String
        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    public var tone: NudgeTone
    public var custom: CustomReminders

    /// The tone's built-in lines, without custom reminders.
    public init(tone: NudgeTone) {
        self.init(tone: tone, custom: CustomReminders())
    }

    public init(tone: NudgeTone, custom: CustomReminders) {
        self.tone = tone
        self.custom = custom
    }

    /// Tone plus your own words: what every surface should use.
    public init(settings: TFSettings) {
        self.init(tone: settings.tone, custom: settings.customReminders)
    }

    // MARK: Your own words

    /// Puts a moment's custom text on a built-in line. The one rule, used everywhere:
    ///
    /// 1. No custom text for the moment (missing, or empty after trimming): the built-in line.
    /// 2. Otherwise `{task}` is filled in with the task's title, or "your next task".
    /// 3. Filled text of up to `CustomReminders.titleLimit` (40) characters becomes the
    ///    **title**; the built-in body stays, so the line still says what's going on.
    /// 4. Longer text becomes the **body**, under the tone's own short title.
    public func apply(_ moment: ReminderMoment, to builtIn: Line, task: String?) -> Line {
        guard let text = custom.text(for: moment) else { return builtIn }
        let filled = CustomReminders.fill(text, task: task)
        if filled.count <= CustomReminders.titleLimit {
            return Line(title: filled, body: builtIn.body)
        }
        return Line(title: builtIn.title, body: filled)
    }

    /// A representative line for a moment, with your words applied: the first, gentlest
    /// nudge of the moment. Used for Settings placeholders and previews.
    public func sample(_ moment: ReminderMoment, task: String?) -> Line {
        switch moment {
        case .restOver: return restOver(level: 1, next: task)
        case .stuck: return stuck(level: 1, task: task)
        case .longFocus: return stillOnIt(task: task)
        case .idle: return idle(level: 1, next: task, left: 3)
        case .paused: return paused(level: 1, task: task)
        case .bootOut: return bootOut(site: "Instagram", task: task)
        case .shield: return shield(during: .focus, task: task, minutesIn: 23)
        case .budgetWarning: return budgetWarning(minutesLeft: 2, task: task)
        case .budgetSpent: return budgetSpent(subtitle: "Instagram is locked for 15 more min.", task: task)
        case .passEnding: return passEnding(task: task)
        }
    }

    private func quoted(_ title: String?) -> String {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return "your next task"
        }
        return "“\(title)”"
    }

    // MARK: Rest overrun

    public func restOver(level: Int, next: String?) -> Line {
        apply(.restOver, to: builtInRestOver(level: level, next: next), task: next)
    }

    private func builtInRestOver(level: Int, next: String?) -> Line {
        let task = quoted(next)
        switch (tone, level) {
        case (.calm, 1): return Line(title: "Rest is over", body: "Ready when you are — \(task).")
        case (.calm, 2): return Line(title: "Still resting", body: "\(task) is waiting for you.")
        case (.calm, _): return Line(title: "Let's get it back", body: "One small step on \(task) brings the momentum back.")
        case (.direct, 1): return Line(title: "Back in.", body: "Rest's over. Next: \(task).")
        case (.direct, 2): return Line(title: "You said a minute.", body: "Start \(task). Now.")
        case (.direct, _): return Line(title: "Momentum's leaking.", body: "Every minute here costs you. Start \(task).")
        case (.savage, 1): return Line(title: "Rest's over. Move.", body: "Next: \(task).")
        case (.savage, 2): return Line(title: "Wake up.", body: "\(task) won't do itself.")
        case (.savage, _): return Line(title: "Wake the fuck up.", body: "Continue. \(task). Right now.")
        }
    }

    // MARK: Stuck too long

    public func stuck(level: Int, task: String?) -> Line {
        apply(.stuck, to: builtInStuck(level: level, task: task), task: task)
    }

    private func builtInStuck(level: Int, task: String?) -> Line {
        let name = quoted(task)
        switch (tone, level) {
        case (.calm, 1): return Line(title: "Still thinking?", body: "Write the smallest next step for \(name).")
        case (.calm, 2): return Line(title: "Try a smaller step", body: "Break \(name) into something you can do in five minutes.")
        case (.calm, _): return Line(title: "Time to move", body: "Park \(name) with a note and switch to something you can finish.")
        case (.direct, 1): return Line(title: "Name the next step.", body: "What's the smallest move on \(name)?")
        case (.direct, 2): return Line(title: "Thinking became waiting.", body: "Break \(name) down, or switch.")
        case (.direct, _): return Line(title: "Decide.", body: "Do the ugly first version of \(name), or switch tasks.")
        case (.savage, 1): return Line(title: "Stop circling.", body: "Smallest next step on \(name). Write it. Do it.")
        case (.savage, 2): return Line(title: "This isn't thinking.", body: "It's stalling. Break \(name) down or switch.")
        case (.savage, _): return Line(title: "Wake the fuck up.", body: "Ugly first draft of \(name). Go.")
        }
    }

    // MARK: Long focus check-in

    public func stillOnIt(task: String?) -> Line {
        apply(.longFocus, to: builtInStillOnIt(task: task), task: task)
    }

    private func builtInStillOnIt(task: String?) -> Line {
        let name = quoted(task)
        switch tone {
        case .calm: return Line(title: "Still with it?", body: "75 minutes on \(name). Finish it, or take a breath.")
        case .direct: return Line(title: "75 minutes in.", body: "Still on \(name)? Close it out or switch.")
        case .savage: return Line(title: "Still on it?", body: "75 minutes on \(name). Ship it.")
        }
    }

    // MARK: Idle with work left

    public func idle(level: Int, next: String?, left: Int) -> Line {
        apply(.idle, to: builtInIdle(level: level, next: next, left: left), task: next)
    }

    private func builtInIdle(level: Int, next: String?, left: Int) -> Line {
        let task = quoted(next)
        let remaining = left == 1 ? "1 task left" : "\(left) tasks left"
        switch (tone, level) {
        case (.calm, 1): return Line(title: "Ready for the next one?", body: "\(remaining). Next: \(task).")
        case (.calm, 2): return Line(title: "Your list is waiting", body: "Start \(task) to keep today moving.")
        case (.calm, _): return Line(title: "Let's restart", body: "One task. \(task). Just begin.")
        case (.direct, 1): return Line(title: "Pick it back up.", body: "\(remaining). Next: \(task).")
        case (.direct, 2): return Line(title: "The day is moving without you.", body: "Start \(task).")
        case (.direct, _): return Line(title: "Back to work.", body: "\(remaining). \(task) first.")
        case (.savage, 1): return Line(title: "Wake up.", body: "\(remaining). Next: \(task).")
        case (.savage, 2): return Line(title: "Still scrolling?", body: "Put it down. \(task). Now.")
        case (.savage, _): return Line(title: "Wake the fuck up and continue.", body: "\(remaining). \(task) is waiting.")
        }
    }

    /// Paused on a task for a while: come back to it.
    public func paused(level: Int, task: String?) -> Line {
        apply(.paused, to: builtInPaused(level: level, task: task), task: task)
    }

    private func builtInPaused(level: Int, task: String?) -> Line {
        let name = quoted(task)
        switch (tone, level) {
        case (.calm, 1): return Line(title: "Ready to pick it back up?", body: "\(name) is paused right where you left it.")
        case (.calm, 2): return Line(title: "Still paused", body: "Resume \(name). The clock picks up where it stopped.")
        case (.calm, _): return Line(title: "Let's get going again", body: "One tap: resume \(name).")
        case (.direct, 1): return Line(title: "Pause over?", body: "Resume \(name).")
        case (.direct, 2): return Line(title: "Still paused.", body: "\(name) is waiting. Resume it.")
        case (.direct, _): return Line(title: "Back to work.", body: "Resume \(name).")
        case (.savage, 1): return Line(title: "Break's over.", body: "Resume \(name).")
        case (.savage, 2): return Line(title: "Still paused?", body: "Put the phone down. Resume \(name).")
        case (.savage, _): return Line(title: "Wake the fuck up and resume.", body: "\(name) is waiting where you left it.")
        }
    }

    // MARK: Boot-outs (doom-scroll guard, shields, overlay)

    /// Shown when a doom-scroll guard kicks you out of a feed.
    public func bootOut(site: String?, task: String?) -> Line {
        apply(.bootOut, to: builtInBootOut(site: site, task: task), task: task)
    }

    private func builtInBootOut(site: String?, task: String?) -> Line {
        let place = site.map { " of \($0)" } ?? ""
        let back = task.map { "Back to “\($0)”." } ?? "Back to what matters."
        switch tone {
        case .calm: return Line(title: "That's enough scrolling", body: "Taking you out\(place). \(back)")
        case .direct: return Line(title: "You're scrolling.", body: "Booted out\(place). \(back)")
        case .savage: return Line(title: "Wake the fuck up.", body: "Doom-scroll detected. Booted out\(place). \(back)")
        }
    }

    /// The whole shield for an app or site blocked while you work, your words applied.
    public func shield(during mode: FlowMode, task: String?, minutesIn: Int?) -> Line {
        let builtIn = Line(title: shieldTitle(during: mode), body: shieldSubtitle(task: task, minutesIn: minutesIn))
        return apply(.shield, to: builtIn, task: task)
    }

    /// Built-in shield title when an app is blocked during focus (no custom text).
    public func shieldTitle(during mode: FlowMode) -> String {
        switch (tone, mode) {
        case (_, .think): return "Think. Don't scroll."
        case (.calm, _): return "Not right now"
        case (.direct, _): return "Not now."
        case (.savage, _): return "Wake up."
        }
    }

    public func shieldSubtitle(task: String?, minutesIn: Int?) -> String {
        guard let task, !task.isEmpty else {
            return tone == .savage ? "You opened this on autopilot. Close it." : "This app is shielded while you focus."
        }
        if let minutesIn, minutesIn > 0 {
            return "You're \(minutesIn) min into “\(task)”. Get back to it."
        }
        return "You're on “\(task)”. Get back to it."
    }

    /// The drift guard noticed you've been somewhere that isn't your task.
    public func drift(task: String, label: String, minutes: Int) -> Line {
        let name = quoted(task)
        let time = minutes == 1 ? "1 min" : "\(minutes) min"
        switch tone {
        case .calm: return Line(title: "Drifted from \(name)?", body: "\(time) on \(label). Ready to head back?")
        case .direct: return Line(title: "That's not \(name).", body: "\(time) on \(label). Back to it.")
        case .savage: return Line(title: "Wake up.", body: "\(time) on \(label). That isn't \(name).")
        }
    }

    /// The heads-up a couple of minutes before the scroll budget shields your apps.
    public func budgetWarning(minutesLeft: Int, task: String?) -> Line {
        apply(.budgetWarning, to: builtInBudgetWarning(minutesLeft: minutesLeft, task: task), task: task)
    }

    private func builtInBudgetWarning(minutesLeft: Int, task: String?) -> Line {
        let left = minutesLeft == 1 ? "1 minute" : "\(minutesLeft) minutes"
        let back = task.map { " Back to “\($0)”?" } ?? ""
        switch tone {
        case .calm: return Line(title: "Still scrolling?", body: "\(left) left, then your apps lock for a while.\(back)")
        case .direct: return Line(title: "Still scrolling?", body: "\(left) left, then it's locked.\(back)")
        case .savage: return Line(title: "Still scrolling?", body: "\(left) left. Then it's locked.\(back)")
        }
    }

    /// One minute before a Post or reply pass closes, your words applied.
    public func passEnding(task: String?) -> Line {
        apply(.passEnding, to: builtInPassEnding, task: task)
    }

    /// One minute before a Post or reply pass closes, without a task to name.
    public var passEnding: Line {
        passEnding(task: nil)
    }

    private var builtInPassEnding: Line {
        switch tone {
        case .calm: return Line(title: "1 minute left", body: "Finish your post or message — the app closes soon.")
        case .direct: return Line(title: "1 minute left.", body: "Send it or post it. Then it closes.")
        case .savage: return Line(title: "1 minute left.", body: "Post it, send it, get out.")
        }
    }

    /// The shield when the scroll budget is spent: the tone's title over `subtitle`
    /// (which the shield builds: what's locked and for how long), your words applied.
    public func budgetSpent(subtitle: String, task: String?) -> Line {
        apply(.budgetSpent, to: Line(title: budgetSpentTitle, body: subtitle), task: task)
    }

    /// Built-in shield title when the daily scroll budget is spent (no custom text).
    public var budgetSpentTitle: String {
        switch tone {
        case .calm: return "Scroll time's up"
        case .direct: return "Budget spent."
        case .savage: return "Wake the fuck up."
        }
    }
}
