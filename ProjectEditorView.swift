import SwiftUI

struct ProjectEditorView: View {
    @ObservedObject var model: NarrationWorkspaceModel
    @ObservedObject var voiceLibrary: VoiceLibrary
    let onManageVoices: () -> Void

    private var selectedVoice: VoiceProfile? {
        voiceLibrary.profiles.first(where: { $0.id == model.draftVoiceID })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                articleInput

                if let project = model.selectedProject, !project.segments.isEmpty {
                    segmentSection(project)
                    generationSection(project)
                }

                statusBar
            }
            .frame(maxWidth: 920)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.975, green: 0.982, blue: 0.99))
        .onAppear {
            model.setDefaultVoiceIfNeeded(voiceLibrary.selectedProfile.id)
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("声音导演")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color(red: 0.18, green: 0.41, blue: 0.78))
                Text("把知识讲清楚，\n也讲得像人。")
                    .font(.system(size: 31, weight: .semibold, design: .serif))
                    .lineSpacing(2)
                Text("应用会识别标题、定义、举例、疑问和结论，再逐段安排表达与停顿。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("完全离线")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12), in: Capsule())
                Text("普通话 · 最多 3000 字")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var articleInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("文章与音色")
                    .font(.headline)
                Spacer()
                Text(model.characterCountLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        model.draftText.count > NarrationProject.maximumCharacterCount
                            ? Color.red
                            : Color.secondary
                    )
            }

            TextField("项目名称（可不填）", text: $model.draftName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("朗读项目名称")

            TextEditor(
                text: Binding(
                    get: { model.draftText },
                    set: { model.updateDraftText($0) }
                )
            )
                .font(.system(size: 15.5))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            model.draftText.count > NarrationProject.maximumCharacterCount
                                ? Color.red.opacity(0.7)
                                : Color.black.opacity(0.08),
                            lineWidth: 1
                        )
                }
                .frame(minHeight: 190)
                .accessibilityLabel("要制作成朗读音频的文章")
                .accessibilityHint("第一版最多支持 3000 个字")

            HStack(spacing: 10) {
                Picker(
                    "朗读音色",
                    selection: Binding(
                        get: { model.draftVoiceID },
                        set: { model.updateDraftVoiceID($0) }
                    )
                ) {
                    ForEach(voiceLibrary.profiles) { voice in
                        Text(voice.name).tag(voice.id)
                    }
                }
                .frame(maxWidth: 300)
                .accessibilityLabel("朗读音色")

                Button("管理音色") { onManageVoices() }
                Spacer()
                Button(model.selectedProject == nil ? "分析朗读方式" : "重新分析并保存") {
                    model.analyzeAndSave()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canAnalyze)
                .help(model.canAnalyze ? "识别文章结构并安排朗读" : "请先输入 3000 字以内的文章并选择音色")
            }
        }
        .padding(18)
        .background(Color(red: 0.925, green: 0.949, blue: 0.978), in: RoundedRectangle(cornerRadius: 16))
    }

    private func segmentSection(_ project: NarrationProject) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("朗读分镜")
                    .font(.title3.weight(.semibold))
                Text("\(project.segments.count) 段")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("蓝色节拍线表示每段的表达力度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(
                    value: Binding(
                        get: { model.commonSpeedFactor },
                        set: { model.applySpeedToAll($0) }
                    ),
                    in: NarrationSegment.minimumSpeedFactor...NarrationSegment.maximumSpeedFactor,
                    step: 0.1
                ) {
                    Text(String(format: "全文 %.1f×", model.commonSpeedFactor))
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                .accessibilityLabel("全文成品语速")
                .accessibilityValue(String(format: "%.1f 倍", model.commonSpeedFactor))
            }

            ForEach(project.segments) { segment in
                SegmentEditorRow(
                    segment: segment,
                    onExpression: { model.updateSegment(id: segment.id, expression: $0) },
                    onSpeed: { model.updateSegment(id: segment.id, speedFactor: $0) },
                    onPause: { model.updateSegment(id: segment.id, pause: $0) },
                    onPlay: { model.playSegment(segment) }
                )
            }
        }
    }

    private func generationSection(_ project: NarrationProject) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("生成与成品")
                        .font(.title3.weight(.semibold))
                    Text("已完成 \(model.completedSegmentCount) / \(project.segments.count) 段")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if model.estimatedFinalDuration > 0 {
                        Text("预计成品 \(formattedDuration(model.estimatedFinalDuration))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.isFinishing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在制作朗读成品")
                }
                Button(model.allSegmentsCompleted ? "重新检查全文" : "生成全文") {
                    guard let selectedVoice else { return }
                    model.generateAll(using: selectedVoice)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canGenerate || selectedVoice == nil)

                Button("制作三种成品") { model.makeFinalAudio() }
                    .disabled(!model.allSegmentsCompleted || model.isFinishing)
            }

            if model.isGenerating, let progress = model.queueProgress {
                GenerationProgressView(progress: progress) {
                    model.cancelGeneration()
                }
            }

            ProjectPlayerBar(
                hasFinalAudio: !model.finalAudioURLs.isEmpty,
                playback: model.playback,
                contextID: project.id,
                onPlay: { model.playFinal() },
                onReveal: { model.revealFinal() }
            )
        }
        .padding(18)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.07), lineWidth: 1)
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var statusBar: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color(red: 0.18, green: 0.41, blue: 0.78))
                .accessibilityHidden(true)
            Text(model.status)
                .font(.subheadline)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("项目状态：\(model.status)")
    }
}
