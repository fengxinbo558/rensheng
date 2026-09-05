import SwiftUI

struct VoiceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: VoiceLibrary
    @StateObject private var capture = AudioCaptureController()

    @State private var name = ""
    @State private var referenceText = Self.readingPrompt
    @State private var authorizationConfirmed = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    private static let readingPrompt = "你好，欢迎使用本地普通话音频概览。我正在录制自己的声音，用于创建只保存在这台电脑上的个人音色。今天天气不错，希望这段清晰自然的朗读可以帮助应用准确地生成普通话语音。"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    nameSection
                    readingPromptSection
                    audioSection
                    authorizationSection
                    errorSection
                }
            }
            Divider()
            footer
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 620)
        .onDisappear {
            capture.cleanupTemporaryRecording()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("录入新音色")
                    .font(.title2.bold())
                Text("录音和音色资料只保存在本机")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("音色名称")
                .font(.headline)
            TextField("例如：我的声音", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("音色名称")
        }
    }

    private var readingPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("照着朗读")
                .font(.headline)
            Text("请在安静环境中自然朗读下面这段文字。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(referenceText)
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            DisclosureGroup("需要使用自己的朗读稿时展开") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("录音内容必须与修改后的文字完全一致。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $referenceText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        .frame(minHeight: 90)
                        .accessibilityLabel("参考音频对应的原文")
                    Button("恢复推荐朗读稿") {
                        referenceText = Self.readingPrompt
                    }
                    .buttonStyle(.link)
                }
                .padding(.top, 6)
            }
        }
    }

    private var audioSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                audioButtons
                HStack {
                    Image(systemName: capture.sourceAudioURL == nil ? "waveform.badge.plus" : "waveform.circle.fill")
                        .foregroundStyle(capture.sourceAudioURL == nil ? Color.secondary : Color.green)
                    Text(capture.sourceLabel)
                        .lineLimit(1)
                    Spacer()
                }
                Text(capture.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let quality = capture.qualitySummary {
                    HStack(spacing: 6) {
                        Image(systemName: quality.level == .good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        Text(quality.detailLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(quality.level == .good ? Color.green : Color.orange)

                    if quality.level == .poor, quality.clippingFraction <= 0.0001 {
                        Text("音量偏低，但保存时会自动增益和降噪")
                            .font(.caption)
                            .foregroundStyle(StudioPalette.blueDeep)
                    } else if quality.clippingFraction > 0.0001 {
                        Text("检测到爆音，请降低输入音量后重新录制")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(4)
        } label: {
            Text("参考音频")
        }
    }

    private var audioButtons: some View {
        HStack(spacing: 10) {
            if capture.isRecording {
                Button("停止录音") { capture.toggleRecording() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else {
                Button("开始录音") { capture.toggleRecording() }
            }

            Button("导入音频…") { capture.importAudio() }
                .disabled(capture.isRecording)
            Button("试听") { capture.playReference() }
                .disabled(capture.sourceAudioURL == nil || capture.isRecording)
            Spacer()
            if capture.isRecording {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                Text(capture.recordingDurationLabel)
                    .monospacedDigit()
            }
        }
    }

    private var authorizationSection: some View {
        Toggle(isOn: $authorizationConfirmed) {
            Text("我确认这是本人的声音，或已获得声音所有者的明确授权")
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Text("建议 10～30 秒；应用会保留原录音，并自动选择更自然的参考版本")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }
            Button("保存音色") { saveVoice() }
                .buttonStyle(.borderedProminent)
                // Keep the action available so a missing field produces a clear
                // explanation instead of an apparently broken grey button.
                .disabled(capture.isRecording || isSaving)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func saveVoice() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText = referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            errorMessage = "请先填写音色名称"
            return
        }
        guard !cleanText.isEmpty else {
            errorMessage = "请填写参考音频对应的朗读文字"
            return
        }
        guard let sourceAudioURL = capture.sourceAudioURL else {
            errorMessage = "请先录音或导入一段参考音频"
            return
        }
        guard let quality = capture.qualitySummary else {
            errorMessage = "音频还没有完成检查，请重新导入后再试"
            return
        }
        guard quality.clippingFraction <= 0.0001 else {
            errorMessage = "这段音频检测到爆音，请降低输入音量后重新录制"
            return
        }
        guard authorizationConfirmed else {
            errorMessage = "请先确认声音授权"
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            try library.createVoice(
                name: name,
                referenceText: referenceText,
                sourceAudioURL: sourceAudioURL
            )
            capture.cleanupTemporaryRecording()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
