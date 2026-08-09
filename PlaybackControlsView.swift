import SwiftUI

struct PlaybackControlsView: View {
    @ObservedObject var playback: PlaybackController
    let contextID: String
    let fallbackTitle: String
    let canStart: Bool
    let onStart: () -> Void

    private var isCurrentContext: Bool {
        playback.controls(context: contextID)
    }

    private var displayedCurrentTime: TimeInterval {
        isCurrentContext ? playback.currentTime : 0
    }

    private var displayedDuration: TimeInterval {
        isCurrentContext ? playback.duration : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(primaryLabel) {
                    if isCurrentContext {
                        playback.togglePlayback()
                    } else {
                        onStart()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isCurrentContext && !canStart)
                .accessibilityLabel(primaryLabel)

                Button("停止播放") { playback.stop() }
                    .disabled(!isCurrentContext || playback.state == .stopped)

                Text(isCurrentContext ? playback.title : fallbackTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()

                Stepper(
                    value: Binding(
                        get: { playback.rate },
                        set: { playback.setRate($0) }
                    ),
                    in: NarrationSegment.minimumSpeedFactor...NarrationSegment.maximumSpeedFactor,
                    step: 0.1
                ) {
                    Text(String(format: "试听 %.1f×", playback.rate))
                        .font(.caption.monospacedDigit())
                }
                .disabled(!isCurrentContext)
                .accessibilityLabel("试听速度")
                .accessibilityValue(String(format: "%.1f 倍", playback.rate))
            }

            HStack(spacing: 9) {
                Text(playback.formattedTime(displayedCurrentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { displayedCurrentTime },
                        set: { playback.seek(to: $0) }
                    ),
                    in: 0...max(displayedDuration, 0.01)
                )
                .disabled(!isCurrentContext)
                .accessibilityLabel("播放进度")
                .accessibilityValue(
                    "已播放 \(playback.formattedTime(displayedCurrentTime))，音频共 \(playback.formattedTime(displayedDuration))"
                )
                Text(playback.formattedTime(displayedDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if isCurrentContext, let message = playback.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if isCurrentContext, playback.rate < 0.6 || playback.rate > 2.0 {
                Label("极端试听速度可能出现明显拉伸感", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var primaryLabel: String {
        isCurrentContext ? playback.primaryActionLabel : "播放"
    }
}
