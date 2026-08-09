import SwiftUI

struct ProjectEditorView: View {
    @ObservedObject var model: NarrationWorkspaceModel
    @ObservedObject var voiceLibrary: VoiceLibrary
    let onManageVoices: () -> Void

    @State private var isAdvancedEditorExpanded = false

    private var selectedVoice: VoiceProfile? {
        voiceLibrary.profiles.first(where: { $0.id == model.draftVoiceID })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                articleInput

                if let project = model.selectedProject, !project.segments.isEmpty {
                    generationSection(project)
                    advancedEditor(project)
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
                Text("选择音色、粘贴文章，剩下的交给应用。")
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
                Text("要朗读的内容")
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
                .frame(minHeight: 210)
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

                Button("录入新音色") { onManageVoices() }
                Spacer()

                if model.isGenerating || model.isFinishing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(primaryActionLabel) {
                    guard let selectedVoice else { return }
                    model.startGeneration(using: selectedVoice)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    !model.canStartGeneration
                        || selectedVoice == nil
                        || !model.finalAudioURLs.isEmpty
                )
                .help("自动分析、保存并生成完整音频")
            }
        }
        .padding(18)
        .background(Color(red: 0.925, green: 0.949, blue: 0.978), in: RoundedRectangle(cornerRadius: 16))
    }

    private var primaryActionLabel: String {
        if model.isGenerating { return "正在生成…" }
        if model.isFinishing { return "正在制作成品…" }
        if !model.finalAudioURLs.isEmpty { return "音频已生成" }
        if model.completedSegmentCount > 0 { return "继续生成" }
        return "生成音频"
    }

    private func generationSection(_ project: NarrationProject) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("生成结果")
                        .font(.title3.weight(.semibold))
                    Text("已完成 \(model.completedSegmentCount) / \(project.segments.count) 个声音片段")
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
                    Label("正在自动制作 WAV、M4A 和 MP3", systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    private func advancedEditor(_ project: NarrationProject) -> some View {
        DisclosureGroup(isExpanded: $isAdvancedEditorExpanded) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    TextField("项目名称（可不填）", text: $model.draftName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                        .accessibilityLabel("朗读项目名称")
                        .onSubmit { model.saveProjectName() }
                    Button("保存名称") { model.saveProjectName() }
                        .disabled(model.isGenerating || model.isFinishing)
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { model.commonSpeedFactor },
                            set: { model.applySpeedToAll($0) }
                        ),
                        in: NarrationSegment.minimumSpeedFactor...NarrationSegment.maximumSpeedFactor,
                        step: 0.1
                    ) {
                        Text(String(format: "全文成品 %.1f×", model.commonSpeedFactor))
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    .disabled(model.isGenerating || model.isFinishing)
                }

                Text("只在声音不满意时修改。每段可以修正朗读文字、调整成品节奏、切换版本或单独重做。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(project.segments) { segment in
                    SegmentEditorRow(
                        segment: segment,
                        isBusy: model.isGenerating || model.isFinishing,
                        onTextSave: { model.updateSegmentText(id: segment.id, text: $0) },
                        onSpeed: { model.updateSegment(id: segment.id, speedFactor: $0) },
                        onPause: { model.updateSegment(id: segment.id, pause: $0) },
                        onCandidate: { model.selectCandidate(segmentID: segment.id, candidateID: $0) },
                        onRegenerate: {
                            guard let selectedVoice else { return }
                            model.regenerateSegment(id: segment.id, using: selectedVoice)
                        },
                        onPlay: { model.playSegment(segment) }
                    )
                }
            }
            .padding(.top, 14)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("高级编辑")
                        .font(.headline)
                    Text("\(project.segments.count) 个片段 · 正常情况下无需打开")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
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
