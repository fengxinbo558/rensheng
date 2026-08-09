import AppKit
import AVFoundation
import UniformTypeIdentifiers

@MainActor
final class AudioCaptureController: NSObject, ObservableObject {
    @Published private(set) var sourceAudioURL: URL?
    @Published private(set) var sourceLabel = "尚未录入参考音频"
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var status = "建议在安静环境朗读 10～30 秒"
    @Published private(set) var qualitySummary: AudioQualitySummary?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var recordingStartedAt: Date?
    private var ownedTemporaryAudioURL: URL?

    var recordingDurationLabel: String {
        let seconds = Int(recordingDuration.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func importAudio() {
        let panel = NSOpenPanel()
        panel.title = "选择参考音频"
        panel.message = "支持 WAV、M4A、MP3 等 macOS 可读取的音频格式"
        panel.prompt = "导入"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        stopRecording()
        cleanupTemporaryRecording()
        sourceAudioURL = url
        sourceLabel = url.lastPathComponent
        updateQualityStatus(for: url)
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            requestPermissionAndRecord()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        if let started = recordingStartedAt {
            recordingDuration = Date().timeIntervalSince(started)
        }
        recordingStartedAt = nil
        isRecording = false
        if let sourceAudioURL {
            updateQualityStatus(for: sourceAudioURL)
        } else {
            status = "录音完成，可以试听或保存"
        }
    }

    func playReference() {
        guard let sourceAudioURL else { return }
        do {
            player = try AVAudioPlayer(contentsOf: sourceAudioURL)
            player?.prepareToPlay()
            player?.play()
            status = "正在试听参考音频"
        } catch {
            status = "试听失败：\(error.localizedDescription)"
        }
    }

    func cleanupTemporaryRecording() {
        stopRecording()
        if let ownedTemporaryAudioURL {
            try? FileManager.default.removeItem(at: ownedTemporaryAudioURL)
        }
        ownedTemporaryAudioURL = nil
        qualitySummary = nil
    }

    private func requestPermissionAndRecord() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecording()
        case .notDetermined:
            status = "等待麦克风权限…"
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.startRecording()
                    } else {
                        self.status = "未获得麦克风权限，也可以改用导入音频"
                    }
                }
            }
        case .denied, .restricted:
            status = "麦克风权限未开启，也可以改用导入音频"
        @unknown default:
            status = "无法确认麦克风权限，请改用导入音频"
        }
    }

    private func startRecording() {
        do {
            cleanupTemporaryRecording()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LocalAudioProbe-Recordings", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appendingPathComponent("voice-\(UUID().uuidString).wav")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.prepareToRecord(), recorder.record() else {
                throw AudioCaptureError.couldNotStart
            }
            self.recorder = recorder
            ownedTemporaryAudioURL = url
            sourceAudioURL = url
            sourceLabel = "新录音.wav"
            qualitySummary = nil
            recordingDuration = 0
            recordingStartedAt = Date()
            isRecording = true
            status = "正在录音，请按参考原文朗读"
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let started = self.recordingStartedAt else { return }
                    self.recordingDuration = Date().timeIntervalSince(started)
                }
            }
        } catch {
            isRecording = false
            status = "录音失败：\(error.localizedDescription)"
        }
    }

    private func updateQualityStatus(for url: URL) {
        do {
            let quality = try AudioProcessor.analyzeAudio(at: url)
            qualitySummary = quality
            status = quality.shortLabel
        } catch {
            qualitySummary = nil
            status = "已选择音频，保存时将检查质量"
        }
    }
}

enum AudioCaptureError: LocalizedError {
    case couldNotStart

    var errorDescription: String? {
        "无法开始录音"
    }
}
