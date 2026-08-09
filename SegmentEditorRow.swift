import SwiftUI

struct SegmentEditorRow: View {
    let segment: NarrationSegment
    let onExpression: (NarrationExpression) -> Void
    let onSpeed: (NarrationSpeed) -> Void
    let onPause: (NarrationPause) -> Void
    let onPlay: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 7) {
                Text(String(format: "%02d", segment.order + 1))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(kindColor)
                RoundedRectangle(cornerRadius: 3)
                    .fill(kindColor)
                    .frame(width: 5, height: barHeight)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(segment.kind.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(kindColor)
                    Spacer()
                    stateLabel
                    Button("播放") { onPlay() }
                        .buttonStyle(.borderless)
                        .disabled(segment.generationState != .completed)
                }

                Text(segment.text)
                    .font(.system(size: 15.5))
                    .lineSpacing(5)
                    .textSelection(.enabled)

                HStack(spacing: 14) {
                    Picker(
                        "表达方式",
                        selection: Binding(get: { segment.expression }, set: onExpression)
                    ) {
                        ForEach(NarrationExpression.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    Picker(
                        "速度",
                        selection: Binding(get: { segment.speed }, set: onSpeed)
                    ) {
                        ForEach(NarrationSpeed.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    Picker(
                        "段后停顿",
                        selection: Binding(get: { segment.pause }, set: onPause)
                    ) {
                        ForEach(NarrationPause.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    Spacer()
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第 \(segment.order + 1) 段，\(segment.kind.label)")
    }

    private var barHeight: CGFloat {
        switch segment.kind {
        case .title, .conclusion: return 42
        case .definition, .example: return 31
        case .question: return 24
        case .transition: return 18
        case .explanation: return 27
        }
    }

    private var kindColor: Color {
        switch segment.kind {
        case .title, .conclusion: return Color(red: 0.18, green: 0.39, blue: 0.77)
        case .definition: return Color(red: 0.22, green: 0.51, blue: 0.58)
        case .example: return Color(red: 0.20, green: 0.55, blue: 0.46)
        case .question: return Color(red: 0.68, green: 0.43, blue: 0.17)
        case .transition: return Color(red: 0.43, green: 0.46, blue: 0.56)
        case .explanation: return Color(red: 0.32, green: 0.43, blue: 0.58)
        }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch segment.generationState {
        case .completed:
            Label("已完成", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .generating:
            Label("生成中", systemImage: "waveform")
                .foregroundStyle(.blue)
        case .failed:
            Label("可重试", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .cancelled:
            Label("已暂停", systemImage: "pause.circle.fill")
                .foregroundStyle(.secondary)
        case .pending:
            Text("等待生成")
                .foregroundStyle(.secondary)
        }
    }
}
