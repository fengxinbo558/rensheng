import SwiftUI

struct ProjectPlayerBar: View {
    let hasFinalAudio: Bool
    @ObservedObject var playback: PlaybackController
    let contextID: String
    let onPlay: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                Button("在访达中显示") { onReveal() }
                    .disabled(!hasFinalAudio)
            }
            PlaybackControlsView(
                playback: playback,
                contextID: contextID,
                fallbackTitle: hasFinalAudio ? "朗读成品" : "尚无可播放成品",
                canStart: hasFinalAudio,
                onStart: onPlay
            )
        }
        .padding(14)
        .background(Color(red: 0.91, green: 0.95, blue: 0.96), in: RoundedRectangle(cornerRadius: 13))
    }
}
