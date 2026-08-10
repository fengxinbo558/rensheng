import AVFoundation
import Foundation

enum PlaybackState: Equatable {
    case empty
    case playing
    case paused
    case stopped
    case finished
    case failed
}

struct PlaybackProgressSnapshot: Equatable {
    let contextID: String
    let position: TimeInterval
    let duration: TimeInterval
    let state: PlaybackState
}

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var state: PlaybackState = .empty
    @Published private(set) var title = "没有载入音频"
    @Published private(set) var contextID: String?
    @Published private(set) var currentURL: URL?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var rate: Double = 1.0
    @Published private(set) var errorMessage: String?
    var onProgressChanged: ((PlaybackProgressSnapshot) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var audioFile: AVAudioFile?
    private var sourceSampleRate = 0.0
    private var baseFrame: AVAudioFramePosition = 0
    private var timer: Timer?
    private var playbackToken = UUID()
    private var lastReportedPosition: TimeInterval = -.infinity
    private var tracksProgress = false

    init() {
        engine.attach(player)
        engine.attach(timePitch)
        timePitch.pitch = 0
        timePitch.overlap = 12
    }

    var hasAudio: Bool {
        audioFile != nil && duration > 0
    }

    var isPlaying: Bool { state == .playing }
    var isPaused: Bool { state == .paused }

    var primaryActionLabel: String {
        switch state {
        case .playing: return "暂停播放"
        case .paused: return "继续播放"
        case .empty, .stopped, .finished, .failed: return "播放"
        }
    }

    func play(
        url: URL,
        title: String,
        contextID: String,
        initialRate: Double = 1.0,
        initialPosition: TimeInterval = 0,
        tracksProgress: Bool = false
    ) throws {
        stopAndUnload()
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard file.length > 0, format.sampleRate > 0 else {
            throw PlaybackControllerError.emptyAudio
        }

        audioFile = file
        currentURL = url
        self.title = title
        self.contextID = contextID
        sourceSampleRate = format.sampleRate
        duration = Double(file.length) / format.sampleRate
        let lastPlayableFrame = max(0, file.length - 1)
        let requestedFrame = AVAudioFramePosition(
            (max(0, initialPosition) * format.sampleRate).rounded()
        )
        baseFrame = min(lastPlayableFrame, requestedFrame)
        currentTime = Double(baseFrame) / format.sampleRate
        lastReportedPosition = -.infinity
        self.tracksProgress = tracksProgress
        setRate(initialRate)

        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        try schedule(from: 0)
        player.play()
        state = .playing
        errorMessage = nil
        startTimer()
        reportProgress(force: true)
    }

    func togglePlayback() {
        switch state {
        case .playing:
            pause()
        case .paused:
            resume()
        case .stopped, .finished, .failed:
            restart()
        case .empty:
            break
        }
    }

    func pause() {
        guard state == .playing else { return }
        updateCurrentTime()
        player.pause()
        state = .paused
        stopTimer()
        reportProgress(force: true)
    }

    func resume() {
        guard state == .paused else { return }
        player.play()
        state = .playing
        startTimer()
    }

    func stop() {
        guard hasAudio else { return }
        updateCurrentTime()
        playbackToken = UUID()
        player.stop()
        baseFrame = 0
        currentTime = 0
        state = .stopped
        stopTimer()
        reportProgress(force: true)
    }

    func stopAndUnload() {
        if hasAudio {
            updateCurrentTime()
            reportProgress(force: true)
        }
        playbackToken = UUID()
        player.stop()
        engine.stop()
        engine.reset()
        stopTimer()
        audioFile = nil
        currentURL = nil
        contextID = nil
        sourceSampleRate = 0
        baseFrame = 0
        currentTime = 0
        duration = 0
        rate = 1.0
        title = "没有载入音频"
        errorMessage = nil
        state = .empty
        lastReportedPosition = -.infinity
        tracksProgress = false
    }

    func seek(to requestedTime: TimeInterval) {
        guard hasAudio, sourceSampleRate > 0 else { return }
        let target = min(max(requestedTime, 0), duration)
        let wasPlaying = state == .playing
        playbackToken = UUID()
        player.stop()
        baseFrame = AVAudioFramePosition((target * sourceSampleRate).rounded())
        currentTime = target
        if target >= duration {
            state = .finished
            stopTimer()
            reportProgress(force: true)
            return
        }
        do {
            try schedule(from: baseFrame)
            if wasPlaying {
                player.play()
                state = .playing
                startTimer()
            } else {
                state = .paused
                stopTimer()
            }
            reportProgress(force: true)
        } catch {
            fail(error)
        }
    }

    func setRate(_ requestedRate: Double) {
        let normalized = NarrationSegment.normalizedSpeedFactor(requestedRate)
        rate = normalized
        timePitch.rate = Float(normalized)
        timePitch.overlap = normalized < 0.6 || normalized > 2.0 ? 24 : 12
    }

    func incrementRate(by amount: Double) {
        setRate(rate + amount)
    }

    func controls(context expectedContextID: String) -> Bool {
        contextID == expectedContextID && hasAudio
    }

    func formattedTime(_ value: TimeInterval) -> String {
        let safe = max(0, value.isFinite ? value : 0)
        let seconds = Int(safe.rounded(.down))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func schedule(from frame: AVAudioFramePosition) throws {
        guard let audioFile else { throw PlaybackControllerError.emptyAudio }
        let remaining = max(0, audioFile.length - frame)
        guard remaining > 0 else {
            state = .finished
            return
        }
        guard remaining <= AVAudioFramePosition(UInt32.max) else {
            throw PlaybackControllerError.audioTooLong
        }
        let token = UUID()
        playbackToken = token
        player.scheduleSegment(
            audioFile,
            startingFrame: frame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.playbackToken == token else { return }
                self.currentTime = self.duration
                self.state = .finished
                self.stopTimer()
                self.reportProgress(force: true)
            }
        }
    }

    private func restart() {
        guard hasAudio else { return }
        playbackToken = UUID()
        player.stop()
        baseFrame = 0
        currentTime = 0
        do {
            if !engine.isRunning { try engine.start() }
            try schedule(from: 0)
            player.play()
            state = .playing
            errorMessage = nil
            startTimer()
        } catch {
            fail(error)
        }
    }

    private func updateCurrentTime() {
        guard state == .playing,
              let renderTime = player.lastRenderTime,
              let nodeTime = player.playerTime(forNodeTime: renderTime),
              sourceSampleRate > 0 else { return }
        let sourceFrame = baseFrame + nodeTime.sampleTime
        currentTime = min(duration, max(0, Double(sourceFrame) / sourceSampleRate))
        reportProgress(force: false)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateCurrentTime() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func reportProgress(force: Bool) {
        guard tracksProgress, let contextID else { return }
        guard force || abs(currentTime - lastReportedPosition) >= 5 else { return }
        lastReportedPosition = currentTime
        onProgressChanged?(
            PlaybackProgressSnapshot(
                contextID: contextID,
                position: currentTime,
                duration: duration,
                state: state
            )
        )
    }

    private func fail(_ error: Error) {
        player.stop()
        stopTimer()
        state = .failed
        errorMessage = error.localizedDescription
    }
}

enum PlaybackControllerError: LocalizedError {
    case emptyAudio
    case audioTooLong

    var errorDescription: String? {
        switch self {
        case .emptyAudio: return "音频没有可播放的内容"
        case .audioTooLong: return "这段音频太长，无法一次载入播放器"
        }
    }
}
