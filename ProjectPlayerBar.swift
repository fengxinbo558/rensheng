import SwiftUI

struct ProjectPlayerBar: View {
    let hasFinalAudio: Bool
    let availableSegmentCount: Int
    let isPreparingPreview: Bool
    let availableExportFormats: [AudioExportFormat]
    let isExporting: Bool
    let savedPosition: TimeInterval
    @ObservedObject var playback: PlaybackController
    let contextID: String
    let onPlay: () -> Void
    let onPlayFromBeginning: () -> Void
    let onReveal: () -> Void
    let onExport: (AudioExportFormat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.18, green: 0.41, blue: 0.78))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(summaryDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if savedPosition > 0, hasFinalAudio || availableSegmentCount > 0 {
                    Button("从头播放") { onPlayFromBeginning() }
                }
                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在导出声音作品")
                }
                Menu("导出成品") {
                    Button(AudioExportFormat.m4a.label) { onExport(.m4a) }
                        .disabled(!availableExportFormats.contains(.m4a))
                    Button(AudioExportFormat.mp3.label) { onExport(.mp3) }
                        .disabled(!availableExportFormats.contains(.mp3))
                    Divider()
                    Button(AudioExportFormat.wav.label) { onExport(.wav) }
                        .disabled(!availableExportFormats.contains(.wav))
                }
                .disabled(availableExportFormats.isEmpty || isExporting)
                .help("把成品保存到你选择的位置")
                Button("在访达中显示") { onReveal() }
                    .disabled(!hasFinalAudio)
            }
            PlaybackControlsView(
                playback: playback,
                contextID: contextID,
                fallbackTitle: hasFinalAudio ? "声音作品" : "尚无可播放成品",
                canStart: (hasFinalAudio || availableSegmentCount > 0) && !isPreparingPreview,
                onStart: onPlay
            )
        }
        .padding(14)
        .background(Color(red: 0.91, green: 0.95, blue: 0.96), in: RoundedRectangle(cornerRadius: 13))
    }

    private var summaryTitle: String {
        if isPreparingPreview { return "正在准备已完成部分…" }
        if hasFinalAudio { return savedPosition > 0 ? "可以继续收听" : "声音作品已就绪" }
        if availableSegmentCount > 0 { return "已经可以开始听" }
        return "第一段完成后即可收听"
    }

    private var summaryDetail: String {
        if hasFinalAudio { return "WAV、M4A 和 MP3 都可在其他设备播放" }
        if availableSegmentCount > 0 { return "已完成 \(availableSegmentCount) 段，后续可以继续生成" }
        return "无需等待全文生成完成"
    }
}
