import AppKit
import AVFoundation
import SwiftUI

enum SynthesisQuality: String, CaseIterable, Identifiable {
    case fast
    case standard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fast: return "快速"
        case .standard: return "标准（推荐）"
        }
    }

    var steps: Int {
        switch self {
        case .fast: return 4
        case .standard: return 8
        }
    }
}

@MainActor
final class ProbeViewModel: ObservableObject {
    @Published var text = "你好，这是一段完全在本地生成的普通话语音。"
    @Published var quality: SynthesisQuality = .standard {
        didSet {
            UserDefaults.standard.set(quality.rawValue, forKey: Self.qualityKey)
        }
    }
    @Published private(set) var status = "轻量离线引擎已就绪"
    @Published private(set) var isGenerating = false
    @Published private(set) var outputURL: URL?

    private var process: Process?
    private var player: AVAudioPlayer?
    private var referencePlayer: AVAudioPlayer?
    private static let qualityKey = "SynthesisQuality"

    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.qualityKey),
           let restored = SynthesisQuality(rawValue: stored) {
            quality = restored
        }
    }

    var canGenerate: Bool {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return !isGenerating && count > 0 && count <= 500
    }

    var characterCountLabel: String {
        "\(text.count) / 500"
    }

    func generate(using voice: VoiceProfile) {
        let requestedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedText.isEmpty, requestedText.count <= 500 else { return }
        guard FileManager.default.fileExists(atPath: voice.referenceAudioPath) else {
            status = "生成失败：所选音色的参考音频不存在"
            return
        }

        let referenceAudio = voice.referenceAudioURL
        let referenceText = voice.referenceText
        let voiceName = voice.name
        let selectedQuality = quality
        isGenerating = true
        outputURL = nil
        status = "正在使用“\(voiceName)”本地生成…"

        let process = Process()
        self.process = process
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let started = Date()
            do {
                try ProbeConfiguration.ensureDataDirectories()
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let stamp = formatter.string(from: Date())
                let shortID = UUID().uuidString.prefix(8)
                let output = ProbeConfiguration.outputDirectory
                    .appendingPathComponent("普通话-\(stamp)-\(shortID).wav")
                let rawOutput = ProbeConfiguration.outputDirectory
                    .appendingPathComponent(".processing-\(UUID().uuidString).wav")
                defer {
                    try? FileManager.default.removeItem(at: rawOutput)
                }

                let model = ProbeConfiguration.model
                process.executableURL = ProbeConfiguration.runtime
                process.arguments = [
                    "--zipvoice-encoder=\(model.appendingPathComponent("encoder.int8.onnx").path)",
                    "--zipvoice-decoder=\(model.appendingPathComponent("decoder.int8.onnx").path)",
                    "--zipvoice-data-dir=\(model.appendingPathComponent("espeak-ng-data").path)",
                    "--zipvoice-lexicon=\(model.appendingPathComponent("lexicon.txt").path)",
                    "--zipvoice-tokens=\(model.appendingPathComponent("tokens.txt").path)",
                    "--zipvoice-vocoder=\(ProbeConfiguration.vocoder.path)",
                    "--reference-audio=\(referenceAudio.path)",
                    "--reference-text=\(referenceText)",
                    "--num-steps=\(selectedQuality.steps)",
                    "--num-threads=2",
                    "--provider=cpu",
                    "--output-filename=\(rawOutput.path)",
                    requestedText,
                ]
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    let data = stderr.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    throw NSError(
                        domain: "LocalAudioProbe",
                        code: Int(process.terminationStatus),
                        userInfo: [
                            NSLocalizedDescriptionKey: message?.isEmpty == false
                                ? message!
                                : "语音进程退出码 \(process.terminationStatus)"
                        ]
                    )
                }
                guard FileManager.default.fileExists(atPath: rawOutput.path) else {
                    throw NSError(
                        domain: "LocalAudioProbe",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "语音进程未生成 WAV 文件"]
                    )
                }

                var postProcessWarning: String?
                do {
                    try AudioProcessor.postProcessOutput(from: rawOutput, to: output)
                } catch {
                    try FileManager.default.moveItem(at: rawOutput, to: output)
                    postProcessWarning = "降噪后处理未完成，已保留原始音频"
                }

                let elapsed = Date().timeIntervalSince(started)
                DispatchQueue.main.async {
                    self?.process = nil
                    self?.isGenerating = false
                    self?.outputURL = output
                    if let postProcessWarning {
                        self?.status = "\(postProcessWarning) · \(String(format: "%.2f 秒", elapsed))"
                    } else {
                        self?.status = String(
                            format: "“%@”%@生成完成，用时 %.2f 秒",
                            voiceName,
                            selectedQuality.label,
                            elapsed
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.process = nil
                    self?.isGenerating = false
                    self?.status = "生成失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
        isGenerating = false
        status = "已取消"
    }

    func play() {
        guard let outputURL else { return }
        do {
            player = try AVAudioPlayer(contentsOf: outputURL)
            player?.prepareToPlay()
            player?.play()
            status = "正在播放本地音频"
        } catch {
            status = "播放失败：\(error.localizedDescription)"
        }
    }

    func playReference(_ voice: VoiceProfile) {
        do {
            referencePlayer = try AVAudioPlayer(contentsOf: voice.referenceAudioURL)
            referencePlayer?.prepareToPlay()
            referencePlayer?.play()
            status = "正在试听“\(voice.name)”的参考音频"
        } catch {
            status = "试听失败：\(error.localizedDescription)"
        }
    }

    func playOriginalReference(_ voice: VoiceProfile) {
        guard let originalAudioURL = voice.originalAudioURL else { return }
        do {
            referencePlayer = try AVAudioPlayer(contentsOf: originalAudioURL)
            referencePlayer?.prepareToPlay()
            referencePlayer?.play()
            status = "正在试听“\(voice.name)”的原始录音"
        } catch {
            status = "试听失败：\(error.localizedDescription)"
        }
    }

    func revealOutput() {
        guard let outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    func openOutputDirectory() {
        do {
            try ProbeConfiguration.ensureDataDirectories()
            NSWorkspace.shared.open(ProbeConfiguration.outputDirectory)
        } catch {
            status = "无法打开保存目录：\(error.localizedDescription)"
        }
    }
}

struct ContentView: View {
    @StateObject private var model = ProbeViewModel()
    @StateObject private var voiceLibrary = VoiceLibrary()
    @State private var showingVoiceEditor = false
    @State private var voiceToDelete: VoiceProfile?
    @State private var showingDeleteConfirmation = false
    @State private var deleteError = ""
    @State private var showingDeleteError = false

    private var selectedVoice: VoiceProfile {
        voiceLibrary.selectedProfile
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("本地普通话音频概览")
                            .font(.title2.bold())
                        Text("GTCRN 本地降噪 · ZipVoice Distill INT8")
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Picker("当前音色", selection: $voiceLibrary.selectedVoiceID) {
                                ForEach(voiceLibrary.profiles) { voice in
                                    Text(voice.name).tag(voice.id)
                                }
                            }
                            .frame(maxWidth: 320)

                            Button(selectedVoice.isBuiltIn ? "试听音色" : "试听降噪音色") {
                                model.playReference(selectedVoice)
                            }

                            if selectedVoice.originalAudioURL != nil {
                                Button("试听原录音") {
                                    model.playOriginalReference(selectedVoice)
                                }
                            }

                            Button("录入新音色") {
                                showingVoiceEditor = true
                            }
                            .buttonStyle(.borderedProminent)

                            if !selectedVoice.isBuiltIn {
                                Button("删除", role: .destructive) {
                                    voiceToDelete = selectedVoice
                                    showingDeleteConfirmation = true
                                }
                            }
                            Spacer()
                        }

                        HStack(spacing: 6) {
                            Image(systemName: selectedVoice.isBuiltIn ? "speaker.wave.2" : "person.wave.2")
                            Text(selectedVoice.isBuiltIn ? "内置测试音色" : "自定义音色 · 资料仅保存在本机")
                            Spacer()
                            Text("共 \(voiceLibrary.profiles.count) 个音色")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let quality = selectedVoice.qualitySummary {
                            Label(
                                quality.shortLabel,
                                systemImage: quality.level == .good
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(quality.level == .good ? Color.green : Color.orange)
                        }

                        if let errorMessage = voiceLibrary.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(4)
                } label: {
                    Text("声音")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("输入普通话")
                        .font(.headline)
                    TextEditor(text: $model.text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                        .frame(minHeight: 150)
                        .accessibilityLabel("要生成的普通话文本")

                    HStack {
                        Text(model.characterCountLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(model.text.count > 500 ? .red : .secondary)
                        Picker("生成质量", selection: $model.quality) {
                            ForEach(SynthesisQuality.allCases) { quality in
                                Text(quality.label).tag(quality)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        .disabled(model.isGenerating)
                        Spacer()
                        if model.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                            Button("取消", role: .cancel) { model.cancel() }
                        } else {
                            Button("使用“\(selectedVoice.name)”生成") {
                                model.generate(using: selectedVoice)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canGenerate)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: model.outputURL == nil ? "info.circle" : "checkmark.circle.fill")
                            .foregroundStyle(model.outputURL == nil ? Color.secondary : Color.green)
                        Text(model.status)
                            .lineLimit(2)
                        Spacer()
                        Button("播放") { model.play() }
                            .disabled(model.outputURL == nil)
                        Button("在访达中显示") { model.revealOutput() }
                            .disabled(model.outputURL == nil)
                        Button("打开保存文件夹") { model.openOutputDirectory() }
                    }

                    Text("音频固定保存到：音乐 / 本地音频概览")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(28)
        }
        .frame(minWidth: 760, minHeight: 640)
        .sheet(isPresented: $showingVoiceEditor) {
            VoiceEditorView(library: voiceLibrary)
        }
        .confirmationDialog(
            "删除自定义音色？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("移到废纸篓", role: .destructive) {
                deleteSelectedVoice()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("“\(voiceToDelete?.name ?? "这个音色")”的本地参考录音和资料将移到废纸篓。")
        }
        .alert("无法删除音色", isPresented: $showingDeleteError) {
            Button("好") {}
        } message: {
            Text(deleteError)
        }
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func deleteSelectedVoice() {
        guard let voiceToDelete else { return }
        do {
            try voiceLibrary.deleteVoice(voiceToDelete)
            self.voiceToDelete = nil
        } catch {
            deleteError = error.localizedDescription
            showingDeleteError = true
        }
    }
}

@main
struct CLTSwiftUIProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}
