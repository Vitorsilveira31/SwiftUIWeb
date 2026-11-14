import AVFoundation
import AVKit
import Foundation
import Observation

/// Owns one AVPlayer and the state the screen reads. AVPlayer is not observable, so a periodic time observer
/// copies position and duration into the state that SwiftUI tracks.
@Observable
@MainActor
final class PlayerViewModel {
    struct State {
        var clips: [Clip] = []
        var clip: Clip?
        var isPlaying = false
        var position: Double = 0
        var duration: Double = 0
        /// A seek requested but not finished. The bar shows it, so quick presses of Back or Forward add up
        /// instead of restarting from the old position.
        var pendingSeek: Double?
        /// The thumb's value while the user drags the scrubber. Nothing seeks until the drag ends, so the picture
        /// does not stutter under the finger.
        var scrubTime: Double?
        var rate: Double = 1
        var isMuted = true
        var volume: Double = 1
        var failure = ""

        /// The position the bar shows: the drag, else a pending seek, else playback.
        var shownTime: Double { scrubTime ?? pendingSeek ?? position }

        /// Whole seconds left, so elapsed and remaining add up to the length.
        var remaining: Double { max(0, floor(duration) - floor(shownTime)) }
    }

    enum Action {
        case appear
        case disappear
        case togglePlayback
        case seekBack
        case seekForward
        case rewind
        case scrub(Double)
        case commitScrub
        case setRate(Double)
        case setMuted(Bool)
        case setVolume(Double)
        case selectClip(Clip)
        case playbackEnded
        case playbackFailed
    }

    let player: AVPlayer
    private(set) var state: State

    private var timeObserver: Any?
    private var seekGeneration = 0

    init(initialState: State = .init(), repository: any ClipRepository) {
        var state = initialState
        let clips = repository.clips()
        state.clips = clips
        state.clip = clips.first
        self.state = state
        if let first = clips.first {
            player = AVPlayer(url: first.url)
        } else {
            player = AVPlayer()
        }
        player.isMuted = state.isMuted
    }

    func send(_ action: Action) {
        switch action {
        case .appear: start()
        case .disappear: stop()
        case .togglePlayback: state.isPlaying ? pause() : play()
        case .seekBack: skip(by: -10)
        case .seekForward: skip(by: 10)
        case .rewind: seek(to: 0)
        case .scrub(let time): state.scrubTime = time
        case .commitScrub: commitScrub()
        case .setRate(let rate): setRate(rate)
        case .setMuted(let muted): setMuted(muted)
        case .setVolume(let volume): setVolume(volume)
        case .selectClip(let clip): choose(clip)
        case .playbackEnded: playbackEnded()
        case .playbackFailed: state.failure = Strings.Player.stoppedPlaying
        }
    }

    private func start() {
        guard timeObserver == nil else { return }
        // 10 Hz is enough for a label to read smoothly and cheap on the main queue.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        play()
    }

    private func stop() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        pause()
    }

    private func play() {
        player.rate = Float(state.rate)
        state.isPlaying = true
    }

    private func pause() {
        player.pause()
        state.isPlaying = false
    }

    private func skip(by seconds: Double) {
        seek(to: state.shownTime + seconds)
    }

    private func seek(to seconds: Double) {
        let upper = state.duration > 0 ? state.duration : seconds
        let target = min(max(0, seconds), upper)
        state.pendingSeek = target
        seekGeneration += 1
        let generation = seekGeneration
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.finishSeek(generation) }
        }
    }

    private func commitScrub() {
        guard let target = state.scrubTime else { return }
        state.scrubTime = nil
        seek(to: target)
    }

    private func setRate(_ rate: Double) {
        state.rate = rate
        // Setting `rate` starts playback, so only a playing player gets it directly; a paused one just remembers
        // it for the next play.
        player.defaultRate = Float(rate)
        if state.isPlaying { player.rate = Float(rate) }
    }

    private func setMuted(_ muted: Bool) {
        state.isMuted = muted
        player.isMuted = muted
    }

    private func setVolume(_ volume: Double) {
        state.volume = volume
        player.volume = Float(volume)
    }

    /// Loops the clip, as the reference does, by returning to the start.
    private func playbackEnded() {
        seekGeneration += 1
        state.pendingSeek = nil
        state.position = 0
        player.seek(to: .zero)
        play()
    }

    private func choose(_ next: Clip) {
        guard next != state.clip else { return }
        state.clip = next
        state.position = 0
        state.duration = 0
        state.pendingSeek = nil
        state.scrubTime = nil
        state.failure = ""
        seekGeneration += 1
        player.replaceCurrentItem(with: AVPlayerItem(url: next.url))
        play()
    }

    private func finishSeek(_ generation: Int) {
        // A newer seek has taken over the pending target; leave it alone.
        if generation == seekGeneration { state.pendingSeek = nil }
    }

    private func tick() {
        let now = player.currentTime().seconds
        if now.isFinite { state.position = now }
        state.isPlaying = player.rate != 0
        guard let item = player.currentItem else { return }
        let total = item.duration.seconds
        if total.isFinite { state.duration = total }
        if state.failure.isEmpty, item.status == .failed {
            state.failure = item.error?.localizedDescription ?? Strings.Player.loadFailed
        }
    }
}
