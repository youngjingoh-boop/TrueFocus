import Foundation

/// Every sentence TrueFocus says to you, in one place, in three tones.
/// Short. Specific. Always names the task, because the task is the point.
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

    public init(tone: NudgeTone) {
        self.tone = tone
    }

    private func quoted(_ title: String?) -> String {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return "your next task"
        }
        return "“\(title)”"
    }

    // MARK: Rest overrun

    public func restOver(level: Int, next: String?) -> Line {
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
        let name = quoted(task)
        switch tone {
        case .calm: return Line(title: "Still with it?", body: "75 minutes on \(name). Finish it, or take a breath.")
        case .direct: return Line(title: "75 minutes in.", body: "Still on \(name)? Close it out or switch.")
        case .savage: return Line(title: "Still on it?", body: "75 minutes on \(name). Ship it.")
        }
    }

    // MARK: Idle with work left

    public func idle(level: Int, next: String?, left: Int) -> Line {
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
        let place = site.map { " of \($0)" } ?? ""
        let back = task.map { "Back to “\($0)”." } ?? "Back to what matters."
        switch tone {
        case .calm: return Line(title: "That's enough scrolling", body: "Taking you out\(place). \(back)")
        case .direct: return Line(title: "You're scrolling.", body: "Booted out\(place). \(back)")
        case .savage: return Line(title: "Wake the fuck up.", body: "Doom-scroll detected. Booted out\(place). \(back)")
        }
    }

    /// Shield title when an app is blocked during focus.
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

    /// The heads-up a couple of minutes before the scroll budget shields your apps.
    public func budgetWarning(minutesLeft: Int, task: String?) -> Line {
        let left = minutesLeft == 1 ? "1 minute" : "\(minutesLeft) minutes"
        let back = task.map { " Back to “\($0)”?" } ?? ""
        switch tone {
        case .calm: return Line(title: "Still scrolling?", body: "\(left) left, then your apps lock for a while.\(back)")
        case .direct: return Line(title: "Still scrolling?", body: "\(left) left, then it's locked.\(back)")
        case .savage: return Line(title: "Still scrolling?", body: "\(left) left. Then it's locked.\(back)")
        }
    }

    /// One minute before a Post or reply pass closes.
    public var passEnding: Line {
        switch tone {
        case .calm: return Line(title: "1 minute left", body: "Finish your post or message — the app closes soon.")
        case .direct: return Line(title: "1 minute left.", body: "Send it or post it. Then it closes.")
        case .savage: return Line(title: "1 minute left.", body: "Post it, send it, get out.")
        }
    }

    /// Shield title when the daily scroll budget is spent.
    public var budgetSpentTitle: String {
        switch tone {
        case .calm: return "Scroll time's up"
        case .direct: return "Budget spent."
        case .savage: return "Wake the fuck up."
        }
    }
}
