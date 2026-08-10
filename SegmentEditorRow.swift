import SwiftUI

struct SegmentEditorRow: View {
    let segment: NarrationSegment
    let isBusy: Bool
    let onTextSave: (String) -> Void
    let onExpression: (NarrationExpression) -> Void
    let onExpressionIntensity: (ExpressionIntensity) -> Void
    let onSpeed: (Double) -> Void
    let onPause: (NarrationPause) -> Void
    let onCandidate: (String) -> Void
    let onRegenerate: () -> Void
    let onPlay: () -> Void

    @State private var isExpanded = false
    @State private var editedText: String

    init(
        segment: NarrationSegment,
        isBusy: Bool,
        onTextSave: @escaping (String) -> Void,
        onExpression: @escaping (NarrationExpression) -> Void,
        onExpressionIntensity: @escaping (ExpressionIntensity) -> Void,
        onSpeed: @escaping (Double) -> Void,
        onPause: @escaping (NarrationPause) -> Void,
        onCandidate: @escaping (String) -> Void,
        onRegenerate: @escaping () -> Void,
        onPlay: @escaping () -> Void
    ) {
        self.segment = segment
        self.isBusy = isBusy
        self.onTextSave = onTextSave
        self.onExpression = onExpression
        self.onExpressionIntensity = onExpressionIntensity
        self.onSpeed = onSpeed
        self.onPause = onPause
        self.onCandidate = onCandidate
        self.onRegenerate = onRegenerate
        self.onPlay = onPlay
        _editedText = State(initialValue: segment.text)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("朗读文字")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editedText)
                        .font(.system(size: 14.5))
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 72)
                        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Text("用于修正人名、多音字或专业词读法")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("保存文字") { onTextSave(editedText) }
                            .disabled(
                                isBusy
                                    || editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || editedText == segment.text
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Picker(
                            "表达情绪",
                            selection: Binding(
                                get: { segment.expression.currentValue },
                                set: onExpression
                            )
                        ) {
                            ForEach(NarrationExpression.userSelectableCases) { item in
                                Text(item.label).tag(item)
                            }
                        }
                        .disabled(isBusy)

                        if segment.expression.supportsIntensity {
                            Picker(
                                "情绪强度",
                                selection: Binding(
                                    get: { segment.expressionIntensity },
                                    set: onExpressionIntensity
                                )
                            ) {
                                ForEach(ExpressionIntensity.allCases) { item in
                                    Text(item.label).tag(item)
                                }
                            }
                            .disabled(isBusy)
                        }
                        Spacer()
                    }
                    .controlSize(.small)

                    Text(
                        segment.expression.supportsIntensity
                            ? "默认使用轻微情绪；只有需要时才提高强度。修改后只重做这一段。"
                            : "自然表达会贴近录音语气，不额外表演。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    Stepper(
                        value: Binding(get: { segment.speedFactor }, set: onSpeed),
                        in: NarrationSegment.minimumSpeedFactor...NarrationSegment.maximumSpeedFactor,
                        step: 0.1
                    ) {
                        Text(String(format: "成品 %.1f×", segment.speedFactor))
                            .font(.caption.monospacedDigit())
                    }
                    .disabled(isBusy)
                    Picker(
                        "段后停顿",
                        selection: Binding(get: { segment.pause }, set: onPause)
                    ) {
                        ForEach(NarrationPause.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .disabled(isBusy)
                    Spacer()
                }
                .controlSize(.small)

                HStack(spacing: 10) {
                    if segment.candidates.count > 1 {
                        Picker(
                            "声音版本",
                            selection: Binding(
                                get: { segment.selectedCandidateID ?? "" },
                                set: onCandidate
                            )
                        ) {
                            ForEach(Array(segment.candidates.enumerated()), id: \.element.id) { index, item in
                                Text("版本 \(index + 1)").tag(item.id)
                            }
                        }
                        .frame(maxWidth: 180)
                        .disabled(isBusy)
                    } else if segment.candidates.count == 1 {
                        Text("已有 1 个声音版本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("重新生成这一段") { onRegenerate() }
                        .disabled(isBusy)
                    Spacer()
                }

                if segment.usesExtremeSpeed {
                    Label("极端成品语速可能出现明显拉伸感", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(String(format: "%02d", segment.order + 1))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(kindColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(segment.kind.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(kindColor)
                        stateLabel
                    }
                    Text(segment.text)
                        .font(.system(size: 14.5))
                        .lineLimit(isExpanded ? 3 : 1)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Button("播放") { onPlay() }
                    .buttonStyle(.borderless)
                    .disabled(segment.generationState != .completed || isBusy)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.07), lineWidth: 1)
        }
        .onChange(of: segment.text) { _, newText in editedText = newText }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第 \(segment.order + 1) 段，\(segment.kind.label)")
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
