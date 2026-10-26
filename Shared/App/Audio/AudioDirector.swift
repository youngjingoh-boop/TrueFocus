import AVFoundation
import Foundation
import TrueFocusKit
#if os(iOS) && canImport(MusicKit)
import MusicKit
#endif

/// The sound of the flow. A short studio cue for each moment (done, rest, stuck, back to it,
/// switching, boot-outs, shutting down), focus music while you work, and a river under
/// micro-rests. Sounds play only on the device that made the change.
///
/// Effects: Sonniss GDC bundle (Rescopic Sound, CB Sounddesign, Orbital Emitter, Doex Studio,
/// Stefano Cremona), royalty-free. Music: TrueFocus originals made with ElevenLabs Music.
@MainActor
final class AudioDirector: FocusEffect {
    static let shared = AudioDirector()

    private var cuePlayers: [FlowCue: AVAudioPlayer] = [:]
    private var music: AVAudioPlayer?
    private var musicTrack: String?
    /// The track that just faded out, kept so a resume picks the music up where it stopped.
    private var parked: (player: AVAudioPlayer, track: String)?
    private var ambience: AVAudioPlayer?
    private var appleMusicActive = false
    private var appleMusicUnavailable = false
    private var fadeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// How loud each cue sits against the others.
    private static let cueVolume: [FlowCue: Float] = [
        .complete: 0.9, .switchTask: 0.55, .go: 0.65, .rest: 0.55, .think: 0.5, .pause: 0.5, .boot: 0.85, .shutdown: 0.8,
    ]

    func focusDidChange(_ snapshot: LiveSnapshot, previous: LiveSnapshot?, settings: TFSettings) {
        let here = snapshot.originDevice == TFDevice.name || snapshot.originDevice.isEmpty
        let choice = settings.focusMusic
        let musicMode = here && snapshot.mode.isWorking && choice != .off
        let restMode = here && snapshot.mode == .rest && settings.restAmbience
        configureSession(sustained: musicMode || restMode)

        if settings.soundEffects, let cue = FlowCue.cue(from: previous, to: snapshot, device: TFDevice.name) {
            play(cue)
        }

        if musicMode {
            // Thinking is quieter than working.
            let volume = Float(settings.musicVolume) * (snapshot.mode == .think ? 0.35 : 1)
            startMusic(choice, volume: volume)
        } else {
            stopMusic()
        }

        if restMode {
            startAmbience()
        } else {
            stopAmbience()
        }
    }

    /// A short sample of a track for the settings picker.
    func preview(_ choice: FocusMusic, volume: Double) {
        guard let track = choice.bundledTrack else {
            stopMusic()
            return
        }
        configureSession(sustained: true)
        startMusic(.drive, volume: Float(volume), track: track)
        let player = music
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.music === player, FocusController.shared.mode != .focus else { return }
            self.stopMusic()
        }
    }

    // MARK: Cues

    private func play(_ cue: FlowCue) {
        let player = cuePlayers[cue] ?? load(cue.file, loops: false)
        guard let player else { return }
        cuePlayers[cue] = player
        player.volume = Self.cueVolume[cue] ?? 0.7
        player.currentTime = 0
        player.play()
    }

    // MARK: Music

    private func startMusic(_ choice: FocusMusic, volume: Float, track: String? = nil) {
        #if os(iOS) && canImport(MusicKit)
        if choice == .appleMusic, track == nil, !appleMusicUnavailable {
            startAppleMusic(fallbackVolume: volume)
            return
        }
        #endif
        guard let name = track ?? choice.bundledTrack else { return }
        if let music, musicTrack == name {
            if !music.isPlaying { music.play() }
            fade(music, to: volume, over: 0.8)
            return
        }
        // Switching tracks: let the old one go, bring the new one in.
        if let old = music { fadeOut(old, over: 0.6) }
        // Back from a pause on the same track: carry on from where it stopped.
        let resumed = parked?.track == name ? parked?.player : nil
        parked = nil
        guard let player = resumed ?? load(name, loops: true) else { return }
        if resumed == nil { player.volume = 0 }
        player.play()
        fade(player, to: volume, over: 1.5)
        music = player
        musicTrack = name
    }

    private func stopMusic() {
        #if os(iOS) && canImport(MusicKit)
        if appleMusicActive {
            appleMusicActive = false
            ApplicationMusicPlayer.shared.pause()
        }
        #endif
        guard let music else { return }
        fadeOut(music, over: 1.2)
        // `stop()` keeps the play position, so the same player can resume later.
        if let musicTrack { parked = (music, musicTrack) }
        self.music = nil
        musicTrack = nil
    }

    #if os(iOS) && canImport(MusicKit)
    /// A focus playlist from Apple Music for subscribers; anyone else hears Drive.
    private func startAppleMusic(fallbackVolume: Float) {
        guard !appleMusicActive else { return }
        appleMusicActive = true
        if let music { fadeOut(music, over: 0.6); self.music = nil; musicTrack = nil }
        Task { @MainActor in
            do {
                guard await MusicAuthorization.request() == .authorized,
                      try await MusicSubscription.current.canPlayCatalogContent else {
                    throw CancellationError()
                }
                var request = MusicCatalogSearchRequest(term: "Pure Focus", types: [Playlist.self])
                request.limit = 1
                guard let playlist = try await request.response().playlists.first else { throw CancellationError() }
                guard appleMusicActive else { return }
                let player = ApplicationMusicPlayer.shared
                player.queue = [playlist]
                player.state.repeatMode = .all
                try await player.play()
            } catch {
                appleMusicUnavailable = true
                guard appleMusicActive else { return }
                appleMusicActive = false
                startMusic(.drive, volume: fallbackVolume)
            }
        }
    }
    #endif

    // MARK: Rest ambience

    private func startAmbience() {
        if let ambience {
            if !ambience.isPlaying { ambience.play() }
            fade(ambience, to: 0.55, over: 2)
            return
        }
        guard let player = load("tf_rest_ambience", loops: true) else { return }
        player.volume = 0
        player.play()
        fade(player, to: 0.55, over: 2.5)
        ambience = player
    }

    private func stopAmbience() {
        guard let ambience else { return }
        fadeOut(ambience, over: 1.5)
        self.ambience = nil
    }

    // MARK: Plumbing

    private func load(_ name: String, loops: Bool) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = loops ? -1 : 0
        player.prepareToPlay()
        return player
    }

    private func fade(_ player: AVAudioPlayer, to volume: Float, over duration: TimeInterval) {
        fadeTasks[ObjectIdentifier(player)]?.cancel()
        fadeTasks[ObjectIdentifier(player)] = nil
        player.setVolume(volume, fadeDuration: duration)
    }

    private func fadeOut(_ player: AVAudioPlayer, over duration: TimeInterval) {
        player.setVolume(0, fadeDuration: duration)
        let id = ObjectIdentifier(player)
        fadeTasks[id]?.cancel()
        fadeTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.1))
            guard !Task.isCancelled else { return }
            player.stop()
            self?.fadeTasks[id] = nil
        }
    }

    /// iPhone: music and the rest river keep playing with the screen locked and mix with other
    /// audio; cues alone follow the silent switch.
    private func configureSession(sustained: Bool) {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let category: AVAudioSession.Category = sustained ? .playback : .ambient
        guard session.category != category else { return }
        try? session.setCategory(category, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }
}
