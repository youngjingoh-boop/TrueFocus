import Foundation

/// Music that plays while you focus.
public enum FocusMusic: String, Codable, CaseIterable, Sendable {
    case off
    /// Driving progressive house, 128 BPM.
    case drive
    /// Liquid drum and bass, 172 BPM.
    case pulse
    /// Upbeat lo-fi house, 112 BPM.
    case flow
    /// Calm ambient focus: warm pads, a slow piano motif, a faint pulse at 60 BPM.
    case calm
    /// A focus station from Apple Music, for subscribers. Falls back to Drive.
    case appleMusic

    public var title: String {
        switch self {
        case .off: return "Off"
        case .drive: return "Drive"
        case .pulse: return "Pulse"
        case .flow: return "Flow"
        case .calm: return "Calm"
        case .appleMusic: return "Apple Music"
        }
    }

    public var subtitle: String {
        switch self {
        case .off: return "Silence"
        case .drive: return "Progressive house · 128 BPM"
        case .pulse: return "Liquid drum & bass · 172 BPM"
        case .flow: return "Lo-fi house · 112 BPM"
        case .calm: return "Ambient focus · 60 BPM"
        case .appleMusic: return "Focus station · subscribers"
        }
    }

    /// The bundled track for this choice (Apple Music falls back to Drive).
    public var bundledTrack: String? {
        switch self {
        case .off: return nil
        case .drive, .appleMusic: return "tf_music_drive"
        case .pulse: return "tf_music_pulse"
        case .flow: return "tf_music_flow"
        case .calm: return "tf_music_calm"
        }
    }

    /// The next choice for a one-tap music button: off → Drive → Pulse → Flow → Calm → off.
    public var next: FocusMusic {
        switch self {
        case .off: return .drive
        case .drive: return .pulse
        case .pulse: return .flow
        case .flow: return .calm
        case .calm, .appleMusic: return .off
        }
    }
}

/// The moments that have a sound.
public enum FlowCue: String, CaseIterable, Sendable {
    /// A task crossed off.
    case complete
    /// Focus moved to another task (juggling, switching).
    case switchTask
    /// Back to work: rest or think is over.
    case go
    /// A micro-rest begins.
    case rest
    /// Stuck: think time.
    case think
    /// The clock stops on a task: a soft two-note settle.
    case pause
    /// Booted out of a doom-scroll. Played where the boot-out happens (`AudioDirector.bootOut()`),
    /// never from a state change: boot counts arrive late and from other devices.
    case boot
    /// The day is shut down.
    case shutdown

    public var file: String {
        switch self {
        case .complete: return "tf_complete"
        case .switchTask: return "tf_switch"
        case .go: return "tf_go"
        case .rest: return "tf_rest"
        case .think: return "tf_think"
        case .pause: return "tf_pause"
        case .boot: return "tf_boot"
        case .shutdown: return "tf_shutdown"
        }
    }

    /// Which cue a state change deserves, if any. Only the device that made the change
    /// plays it, so a task finished on the Mac doesn't chime on the phone too.
    public static func cue(from previous: LiveSnapshot?, to next: LiveSnapshot, device: String) -> FlowCue? {
        guard let previous, previous.updatedAt.timeIntervalSince1970 > 0 else { return nil }
        if next.dayEnded && !previous.dayEnded { return .shutdown }
        guard next.originDevice == device || next.originDevice.isEmpty else { return nil }
        if next.doneToday > previous.doneToday { return .complete }
        switch (previous.mode, next.mode) {
        case (.focus, .think): return .think
        // Pausing has its own quiet settle; resuming is a go (idle → focus, below).
        // Stopping settles like a pause; so does a break you take yourself.
        case (.focus, .idle), (.think, .idle): return next.isPaused || next.stoppedAt != nil ? .pause : nil
        case (.focus, .rest), (.think, .rest): return next.isOnBreak ? .pause : .rest
        case (.rest, .focus), (.think, .focus), (.idle, .focus): return .go
        case (.focus, .focus) where next.taskID != previous.taskID: return .switchTask
        default: return nil
        }
    }
}
