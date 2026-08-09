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
    @Published var engineChoice: SynthesisEngineChoice = .compatibility {
        didSet {
            UserDefaults.standard.set(engineChoice.rawValue, forKey: Self.engineChoiceKey)
        }
    }
    @Published var quality: SynthesisQuality = .standard {
        didSet {
            UserDefaults.standard.set(quality.rawValue, forKey: Self.qualityKey)
        }
    }
    @Published private(set) var status = "轻量离线引擎已就绪"
    @Published private(set) var isGenerating = false
    @Published private(set) var outputURL: URL?

    private var activeEngine: SpeechEngine?
    private var activeGenerationID: UUID?
    private var player: AVAudioPlayer?
    private var referencePlayer: AVAudioPlayer?
    private static let qualityKey = "SynthesisQuality"
    private static let engineChoiceKey = "SynthesisEngineChoice"

    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.qualityKey),
           let restored = SynthesisQuality(rawValue: stored) {
            quality = restored
        }
        let storedChoice = UserDefaults.standard.string(forKey: Self.engineChoiceKey)
            .flatMap(SynthesisEngineChoice.init(rawValue:))
        let preferredChoice = storedChoice ?? .natural
        engineChoice = preferredChoice == .natural && !RuntimeLocator.qwen.isAvailable
            ? .compatibility
            : preferredChoice
        status = engineChoice == .natural
            ? "自然人声引擎已就绪"
            : "兼容模式已就绪"
    }

    var canGenerate: Bool {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return !isGenerating && count > 0 && count <= 500 && selectedEngineIsAvailable
    }

    var characterCountLabel: String {
        "\(text.count) / 500"
    }

    var naturalEngineAvailable: Bool {
        RuntimeLocator.qwen.isAvailable
    }

    var naturalEngineUnavailableMessage: String? {
        let missing = RuntimeLocator.qwen.missingComponents
        return missing.isEmpty ? nil : "自然人声暂不可用：\(missing.joined(separator: "、"))"
    }

    var selectedEngineIsAvailable: Bool {
        engineChoice == .compatibility || naturalEngineAvailable
    }

    func generate(using voice: VoiceProfile) {
        let requestedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedText.isEmpty, requestedText.count <= 500 else { return }
        guard FileManager.default.fileExists(atPath: voice.referenceAudioPath) else {
            status = "生成失败：所选音色的参考音频不存在"
            return
        }

        let engine: SpeechEngine = engineChoice == .natural
            ? QwenSpeechEngine()
            : ZipVoiceSpeechEngine()
        guard engine.isAvailable else {
            status = "生成失败：\(engine.unavailableReason ?? "所需资源未就绪")"
            return
        }

        let voiceName = voice.name
        let selectedQuality = quality
        let generationID = UUID()
        isGenerating = true
        outputURL = nil
        activeEngine = engine
        activeGenerationID = generationID
        status = "正在使用“\(voiceName)”准备\(engine.displayName)…"

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
                let request = SpeechSynthesisRequest(
                    text: requestedText,
                    voice: voice,
                    outputURL: output,
                    zipVoiceSteps: selectedQuality.steps
                )
                let result = try engine.synthesize(request: request) { progress in
                    DispatchQueue.main.async { [weak self] in
                        guard self?.activeGenerationID == generationID else { return }
                        self?.status = "\(engine.displayName) · \(progress.statusLabel)"
                    }
                }

                let elapsed = Date().timeIntervalSince(started)
                DispatchQueue.main.async { [weak self] in
                    guard self?.activeGenerationID == generationID else { return }
                    self?.activeEngine = nil
                    self?.activeGenerationID = nil
                    self?.isGenerating = false
                    self?.outputURL = result.outputURL
                    if let warning = result.warning {
                        self?.status = "\(warning) · \(String(format: "%.2f 秒", elapsed))"
                    } else {
                        self?.status = "“\(voiceName)”\(engine.displayName)生成完成，用时 \(String(format: "%.2f 秒", elapsed))"
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard self?.activeGenerationID == generationID else { return }
                    self?.activeEngine = nil
                    self?.activeGenerationID = nil
                    self?.isGenerating = false
                    if case SpeechEngineError.cancelled = error {
                        self?.status = "已取消"
                    } else {
                        self?.status = "生成失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func cancel() {
        activeGenerationID = nil
        activeEngine?.cancel()
        activeEngine = nil
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

private enum AppSection: String, CaseIterable, Identifiable {
    case projects
    case quick

    var id: String { rawValue }
    var label: String { self == .projects ? "朗读项目" : "快速生成" }
}

struct ContentView: View {
    @StateObject private var model = ProbeViewModel()
    @StateObject private var voiceLibrary = VoiceLibrary()
    @StateObject private var workspaceModel = NarrationWorkspaceModel()
    @State private var selectedSection: AppSection = .projects
    @State private var showingVoiceEditor = false
    @State private var voiceToDelete: VoiceProfile?
    @State private var showingDeleteConfirmation = false
    @State private var deleteError = ""
    @State private var showingDeleteError = false

    private var selectedVoice: VoiceProfile {
        voiceLibrary.selectedProfile
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("应用功能", selection: $selectedSection) {
                    ForEach(AppSection.allCases) { section in
                        Text(section.label).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 290)
                .accessibilityLabel("选择朗读项目或快速生成")
                Spacer()
                Label("所有处理均在本机完成", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()

            if selectedSection == .projects {
                NarrationWorkspaceView(
                    model: workspaceModel,
                    voiceLibrary: voiceLibrary,
                    onManageVoices: { showingVoiceEditor = true }
                )
            } else {
                quickGenerateView
            }
        }
        .frame(minWidth: 980, minHeight: 720)
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

    private var quickGenerateView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("本地普通话音频概览")
                            .font(.title2.bold())
                        Text(model.naturalEngineAvailable ? "本地自然人声 · 完全离线" : "本地语音 · 完全离线")
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

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("声音模式", selection: $model.engineChoice) {
                            Text(SynthesisEngineChoice.natural.label)
                                .tag(SynthesisEngineChoice.natural)
                                .disabled(!model.naturalEngineAvailable)
                            Text(SynthesisEngineChoice.compatibility.label)
                                .tag(SynthesisEngineChoice.compatibility)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 420)
                        .disabled(model.isGenerating)
                        .accessibilityLabel("声音生成模式")

                        if model.engineChoice == .natural {
                            Text("更接近真人的语气和音色；第一次生成需要先载入本地模型。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("占用更低、生成更快，适合资源较少的电脑。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let message = model.naturalEngineUnavailableMessage {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(4)
                } label: {
                    Text("生成方式")
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
                        if model.engineChoice == .compatibility {
                            Picker("生成质量", selection: $model.quality) {
                                ForEach(SynthesisQuality.allCases) { quality in
                                    Text(quality.label).tag(quality)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                            .disabled(model.isGenerating)
                        } else {
                            Label("自然人声 · 自动高质量", systemImage: "waveform.badge.plus")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("正在生成本地语音")
                            Button("取消", role: .cancel) { model.cancel() }
                        } else {
                            Button("使用“\(selectedVoice.name)”生成\(model.engineChoice == .natural ? "自然语音" : "")") {
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
                            .accessibilityLabel("生成状态：\(model.status)")
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
