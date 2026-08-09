import SwiftUI

struct ProjectPlayerBar: View {
    let hasFinalAudio: Bool
    let onPlay: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 0.18, green: 0.41, blue: 0.78))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(hasFinalAudio ? "朗读成品已就绪" : "完成全文后可制作成品")
                    .font(.subheadline.weight(.semibold))
                Text("WAV、M4A 和 MP3 都可在其他设备播放")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("播放成品") { onPlay() }
                .disabled(!hasFinalAudio)
            Button("在访达中显示") { onReveal() }
                .disabled(!hasFinalAudio)
        }
        .padding(14)
        .background(Color(red: 0.91, green: 0.95, blue: 0.96), in: RoundedRectangle(cornerRadius: 13))
    }
}
