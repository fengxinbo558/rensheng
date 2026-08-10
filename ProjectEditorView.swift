import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectEditorView: View {
    @ObservedObject var model: NarrationWorkspaceModel
    @ObservedObject var voiceLibrary: VoiceLibrary
    let onManageVoices: () -> Void

    @State private var isPieceEditorExpanded = false
    @State private var isSourceEditorExpanded = true

    private var selectedVoice: VoiceProfile? {
        voiceLibrary.profiles.first(where: { $0.id == model.draftVoiceID })
    }

    private var sourceExpansionKey: String {
        let projectID = model.selectedProject?.id ?? "new"
        let hasSegments = model.selectedProject?.segments.isEmpty == false
        return "\(projectID)-\(hasSegments)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                if let project = model.selectedProject, !project.segments.isEmpty {
                    PublishingProgressView(
                        progress: PublishingProgress(
                            project: project,
                            availableFormats: Array(model.finalAudioURLs.keys)
                        )
                    )
                    productionControls
                    generationSection(project)
                    sourceEditor(project)
                    pieceEditor(project)
                } else {
                    newProjectInput
                }

                statusBar
            }
            .frame(maxWidth: 920)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.972, green: 0.979, blue: 0.991))
        .onAppear {
            model.setDefaultVoiceIfNeeded(voiceLibrary.selectedProfile.id)
            syncSourceExpansion()
        }
        .onChange(of: sourceExpansionKey) { _, _ in
            syncSourceExpansion()
            isPieceEditorExpanded = false
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("声音导演 · 私人声音出版台")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 0.23, green: 0.44, blue: 0.78))
                Text(heroTitle)
                    .font(.system(size: 29, weight: .semibold, design: .serif))
                    .lineSpacing(2)
                    .lineLimit(2)
                Text(heroSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Label("本地作品库", systemImage: "lock.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.87, green: 0.95, blue: 0.92), in: Capsule())
                Text("普通话 · 最多 30000 字")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heroTitle: String {
        guard let project = model.selectedProject,
              !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "把文稿，做成能反复修改的声音作品。"
        }
        return project.name
    }

    private var heroSubtitle: String {
        model.selectedProject?.segments.isEmpty == false
            ? "修改一段，只重做这一段；成品随时可以继续编辑和导出。"
            : "录一次声音，长期制作；原稿、声音和成品默认留在本机。"
    }

    private var newProjectInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            SourceImportView(
                isBusy: model.isImportingSource,
                onImportText: { model.importPlainText($0) },
                onImportPDF: { model.importPDF($0) },
                onImportWebPage: { model.importWebPage($0) }
            )

            sourceTextHeader(title: "作品原稿")
            sourceTextEditor(minHeight: 220)
            productionControls
        }
        .padding(18)
        .background(
            Color(red: 0.925, green: 0.949, blue: 0.978),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func sourceEditor(_ project: NarrationProject) -> some View {
        DisclosureGroup(isExpanded: $isSourceEditorExpanded) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    TextField("作品名称", text: $model.draftName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("声音作品名称")
                        .onSubmit { model.saveProjectName() }
                    Button("保存名称") { model.saveProjectName() }
                        .disabled(model.isGenerating || model.isFinishing)
                }

                sourceTextHeader(title: "原稿内容")
                sourceTextEditor(minHeight: 180)

                Label(
                    "修改原稿或音色后，点击上方“更新声音作品”；应用会保留没有变化的片段。",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 14)
        } label: {
            HStack(spacing: 11) {
                SourceBadgeView(kind: project.source.kind)
                VStack(alignment: .leading, spacing: 3) {
                    Text("原稿与来源")
                        .font(.headline)
                    Text("\(project.source.title) · \(project.sourceText.count) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(isSourceEditorExpanded ? "收起原稿" : "查看或修改")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.23, green: 0.44, blue: 0.78))
            }
        }
        .padding(17)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .accessibilityHint("展开后可以修改作品名称、原稿和朗读音色")
    }

    private func sourceTextHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Text("默认整理成自然口语，原文始终保留")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(model.characterCountLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    model.draftText.count > NarrationProject.maximumCharacterCount
                        ? Color.red
                        : Color.secondary
                )
        }
    }

    private func sourceTextEditor(minHeight: CGFloat) -> some View {
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
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    model.draftText.count > NarrationProject.maximumCharacterCount
                        ? Color.red.opacity(0.7)
                        : Color.black.opacity(0.08),
                    lineWidth: 1
                )
        }
        .frame(minHeight: minHeight)
        .accessibilityLabel("要制作成声音作品的原稿")
        .accessibilityHint("当前版本最多支持 30000 个字")
    }

    private var productionControls: some View {
        HStack(spacing: 10) {
            Picker(
                "作品音色",
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
            .accessibilityLabel("声音作品音色")

            Button("录入新音色") { onManageVoices() }
            Spacer()

            if model.isGenerating || model.isFinishing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(model.isFinishing ? "正在制作成品" : "正在生成声音")
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
            .help(primaryActionHelp)
        }
        .padding(16)
        .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 0.23, green: 0.44, blue: 0.78).opacity(0.12), lineWidth: 1)
        }
    }

    private var primaryActionLabel: String {
        if model.isGenerating { return "正在制作声音…" }
        if model.isFinishing { return "正在制作成品…" }
        if !model.finalAudioURLs.isEmpty { return "作品已完成" }
        if model.completedSegmentCount > 0 { return "继续制作" }
        if model.selectedProject?.segments.isEmpty == false { return "更新声音作品" }
        return "制作声音作品"
    }

    private var primaryActionHelp: String {
        if model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "先放入或输入一份原稿"
        }
        if model.draftText.count > NarrationProject.maximumCharacterCount {
            return "原稿需要缩短到 30000 字以内"
        }
        if selectedVoice == nil { return "先选择一个可用音色" }
        if !model.finalAudioURLs.isEmpty { return "作品已经完成；修改原稿或音色后可以更新" }
        return "保存原稿、安排朗读稿并制作完整声音作品"
    }

    private func generationSection(_ project: NarrationProject) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("作品成品")
                        .font(.title3.weight(.semibold))
                    Text("已完成 \(model.completedSegmentCount) / \(project.segments.count) 个声音片段")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if model.estimatedFinalDuration > 0 {
                        Text("预计时长 \(formattedDuration(model.estimatedFinalDuration))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.isFinishing {
                    Label("正在统一音量并制作三种格式", systemImage: "waveform")
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
                availableSegmentCount: model.availableSegmentCount,
                isPreparingPreview: model.isPreparingPreview,
                availableExportFormats: AudioExportFormat.allCases.filter {
                    model.finalAudioURLs[$0] != nil
                },
                isExporting: model.isDeliveringExport,
                savedPosition: project.playbackPositionSeconds,
                playback: model.playback,
                contextID: project.id,
                onPlay: { model.playBestAvailableAudio() },
                onPlayFromBeginning: { model.playFromBeginning() },
                onReveal: { model.revealFinal() },
                onExport: { presentExportPanel(format: $0, project: project) }
            )
        }
        .padding(18)
        .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.07), lineWidth: 1)
        }
    }

    private func pieceEditor(_ project: NarrationProject) -> some View {
        DisclosureGroup(isExpanded: $isPieceEditorExpanded) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("朗读方式")
                            .font(.caption.weight(.semibold))
                        Text(project.scriptMode.helpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker(
                        "朗读方式",
                        selection: Binding(
                            get: { project.scriptMode },
                            set: { model.updateScriptMode($0) }
                        )
                    ) {
                        ForEach(NarrationScriptMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                    .disabled(model.isGenerating || model.isFinishing)
                    .accessibilityHint("切换后重新安排朗读短句，原文不会被覆盖")

                    scriptStateLabel(project)
                    Spacer()
                    Button("重新整理朗读稿") { model.reprepareScript() }
                        .disabled(model.isGenerating || model.isFinishing)
                        .help("按当前朗读方式重新整理全文")
                }

                Divider()

                HStack {
                    Text("逐段修改")
                        .font(.subheadline.weight(.semibold))
                    Text("保存文字后，只需重新生成有变化的语义段")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                ForEach(project.segments) { segment in
                    SegmentEditorRow(
                        segment: segment,
                        isBusy: model.isGenerating || model.isFinishing,
                        onTextSave: { model.updateSegmentText(id: segment.id, text: $0) },
                        onRestoreSource: { model.restoreSegmentSource(id: segment.id) },
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
                    Text("编辑作品")
                        .font(.headline)
                    Text("\(project.segments.count) 个语义段 · 修改一段，只重做这一段")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(isPieceEditorExpanded ? "收起" : "展开编辑")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.23, green: 0.44, blue: 0.78))
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .accessibilityHint("展开后可以对照原稿、修改朗读文字并单独重做某一段")
    }

    @ViewBuilder
    private func scriptStateLabel(_ project: NarrationProject) -> some View {
        switch project.scriptState {
        case .pending, .preparing:
            Label("等待整理", systemImage: "text.alignleft")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .completed:
            Label("朗读稿已保存", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .fallback:
            Label("已安全回退", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .help(project.scriptErrorSummary ?? "已改为逐字朗读")
        case .failed:
            Label("整理失败", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .help(project.scriptErrorSummary ?? "可以重新整理或使用逐字朗读")
        }
    }

    private func presentExportPanel(format: AudioExportFormat, project: NarrationProject) {
        guard model.finalAudioURLs[format] != nil else { return }
        let panel = NSSavePanel()
        panel.title = "导出 \(format.fileExtension.uppercased()) 成品"
        panel.prompt = "导出"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(safeFileName(project.name)).\(format.fileExtension)"
        if let contentType = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [contentType]
        }
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            DispatchQueue.main.async {
                model.deliverFinal(format, to: destination)
            }
        }
    }

    private func safeFileName(_ rawName: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let pieces = rawName.components(separatedBy: invalid)
        let clean = pieces.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "声音作品" : String(clean.prefix(80))
    }

    private func syncSourceExpansion() {
        isSourceEditorExpanded = model.selectedProject?.segments.isEmpty != false
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var statusBar: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color(red: 0.23, green: 0.44, blue: 0.78))
                .accessibilityHidden(true)
            Text(model.status)
                .font(.subheadline)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("作品状态：\(model.status)")
    }
}
