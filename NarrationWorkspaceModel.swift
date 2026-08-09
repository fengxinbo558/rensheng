import AppKit
import Foundation

@MainActor
final class NarrationWorkspaceModel: ObservableObject {
    @Published private(set) var projects: [NarrationProject] = []
    @Published private(set) var selectedProject: NarrationProject?
    @Published var draftName = ""
    @Published var draftText = ""
    @Published var draftVoiceID = ""
    @Published private(set) var status = "新建一个朗读项目，粘贴文章后开始分析"
    @Published private(set) var isGenerating = false
    @Published private(set) var isFinishing = false
    @Published private(set) var queueProgress: GenerationQueueProgress?
    @Published private(set) var finalAudioURLs: [AudioExportFormat: URL] = [:]

    private let store: ProjectStore
    private let director = NarrationDirector()
    let playback: PlaybackController
    private var activeQueue: GenerationQueue?

    init(
        store: ProjectStore = ProjectStore(),
        playback: PlaybackController
    ) {
        self.store = store
        self.playback = playback
        reloadProjects()
        if let mostRecentProject = projects.first {
            selectProject(mostRecentProject)
        }
    }

    var characterCountLabel: String {
        "\(draftText.count) / \(NarrationProject.maximumCharacterCount)"
    }

    var canAnalyze: Bool {
        let count = draftText.trimmingCharacters(in: .whitespacesAndNewlines).count
        return !isGenerating
            && !isFinishing
            && count > 0
            && draftText.count <= NarrationProject.maximumCharacterCount
            && !draftVoiceID.isEmpty
    }

    var canGenerate: Bool {
        guard let selectedProject else { return false }
        return !isGenerating && !isFinishing && !selectedProject.segments.isEmpty
    }

    var completedSegmentCount: Int {
        selectedProject?.segments.filter { $0.generationState == .completed }.count ?? 0
    }

    var allSegmentsCompleted: Bool {
        guard let selectedProject, !selectedProject.segments.isEmpty else { return false }
        return selectedProject.segments.allSatisfy { $0.generationState == .completed }
    }

    var commonSpeedFactor: Double {
        guard let segments = selectedProject?.segments, let first = segments.first else { return 1.0 }
        return segments.dropFirst().allSatisfy { abs($0.speedFactor - first.speedFactor) < 0.001 }
            ? first.speedFactor
            : 1.0
    }

    var estimatedFinalDuration: TimeInterval {
        guard let project = selectedProject else { return 0 }
        return project.segments.reduce(0) { total, segment in
            let sourceDuration = segment.candidates
                .first(where: { $0.id == segment.selectedCandidateID })?
                .durationSeconds ?? 0
            return total + sourceDuration / max(segment.speedFactor, 0.1) + pauseSeconds(segment.pause)
        }
    }

    func setDefaultVoiceIfNeeded(_ voiceID: String) {
        if draftVoiceID.isEmpty { draftVoiceID = voiceID }
    }

    func updateDraftText(_ text: String) {
        draftText = text
        refreshDraftAudioAvailability()
    }

    func updateDraftVoiceID(_ voiceID: String) {
        draftVoiceID = voiceID
        refreshDraftAudioAvailability()
    }

    func startNewProject(defaultVoiceID: String) {
        playback.stopAndUnload()
        selectedProject = nil
        draftName = ""
        draftText = ""
        draftVoiceID = defaultVoiceID
        finalAudioURLs = [:]
        queueProgress = nil
        status = "粘贴一篇知识文章，应用会安排自然的段落与停顿"
    }

    func selectProject(_ project: NarrationProject) {
        do {
            playback.stopAndUnload()
            let loaded = try store.loadProject(id: project.id)
            selectedProject = loaded
            draftName = loaded.name
            draftText = loaded.sourceText
            draftVoiceID = loaded.voiceID
            loadFinalURLs(from: loaded)
            status = loaded.segments.isEmpty
                ? "文章已保存，下一步分析朗读方式"
                : "已恢复 \(loaded.segments.count) 个朗读段落"
        } catch {
            status = "项目打开失败：\(error.localizedDescription)"
        }
    }

    func analyzeAndSave() {
        guard canAnalyze else { return }
        do {
            let analyzed = try director.analyze(text: draftText, voiceID: draftVoiceID)
            var project: NarrationProject
            if var existing = selectedProject {
                existing.name = resolvedName()
                existing.sourceText = draftText
                existing.voiceID = draftVoiceID
                existing.updatedAt = Date()
                existing.segments = merge(analyzed: analyzed, with: existing.segments, voiceID: draftVoiceID)
                existing.refreshSegmentFingerprints(invalidateChanged: true)
                existing.exports = []
                project = existing
            } else {
                project = try store.createProject(
                    name: resolvedName(),
                    sourceText: draftText,
                    voiceID: draftVoiceID
                )
                project.segments = analyzed
                project.updatedAt = Date()
            }
            try store.save(project)
            selectedProject = project
            draftName = project.name
            finalAudioURLs = [:]
            reloadProjects(selecting: project.id)
            status = "已分析为 \(project.segments.count) 个朗读段落，可直接生成全文"
        } catch {
            status = "分析失败：\(error.localizedDescription)"
        }
    }

    func updateSegment(
        id: String,
        expression: NarrationExpression? = nil,
        speedFactor: Double? = nil,
        pause: NarrationPause? = nil
    ) {
        guard var project = selectedProject,
              let index = project.segments.firstIndex(where: { $0.id == id }) else { return }
        if let expression { project.segments[index].expression = expression }
        if let speedFactor {
            project.segments[index].speedFactor = NarrationSegment.normalizedSpeedFactor(speedFactor)
        }
        if let pause { project.segments[index].pause = pause }
        project.segments[index].refreshFingerprint(
            voiceID: project.voiceID,
            invalidateChanged: true
        )
        project.updatedAt = Date()
        project.exports = []
        do {
            try store.save(project)
            selectedProject = project
            finalAudioURLs = [:]
            if playback.contextID == project.id { playback.stopAndUnload() }
            reloadProjects(selecting: project.id)
            if expression == nil {
                status = "第 \(project.segments[index].order + 1) 段成品设置已更新；母版保留，无需重新生成"
            } else {
                status = "第 \(project.segments[index].order + 1) 段表达已更新，需要重新生成"
            }
        } catch {
            status = "段落保存失败：\(error.localizedDescription)"
        }
    }

    func applySpeedToAll(_ requestedSpeed: Double) {
        guard var project = selectedProject else { return }
        let speed = NarrationSegment.normalizedSpeedFactor(requestedSpeed)
        for index in project.segments.indices {
            project.segments[index].speedFactor = speed
        }
        project.exports = []
        project.updatedAt = Date()
        do {
            try store.save(project)
            selectedProject = project
            finalAudioURLs = [:]
            if playback.contextID == project.id { playback.stopAndUnload() }
            reloadProjects(selecting: project.id)
            status = String(format: "全文成品语速已设为 %.1f×；段落母版保留", speed)
        } catch {
            status = "全文语速保存失败：\(error.localizedDescription)"
        }
    }

    func generateAll(using voice: VoiceProfile) {
        guard canGenerate, let projectID = selectedProject?.id else { return }
        let engine: SpeechEngine = RuntimeLocator.qwen.isAvailable
            ? QwenSpeechEngine()
            : ZipVoiceSpeechEngine()
        let queue = GenerationQueue(store: store, engine: engine)
        activeQueue = queue
        isGenerating = true
        queueProgress = GenerationQueueProgress(
            completed: completedSegmentCount,
            total: selectedProject?.segments.count ?? 0,
            currentSegment: max(1, completedSegmentCount + 1),
            status: "正在准备本地自然人声"
        )
        status = "开始逐段生成；已经完成的段落会自动保留"
        let owner = self

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let summary = try queue.run(projectID: projectID, voice: voice) { progress in
                    Task { @MainActor [weak owner] in
                        guard owner?.activeQueue === queue else { return }
                        owner?.queueProgress = progress
                        owner?.status = progress.status
                        owner?.reloadSelectedProject()
                    }
                }
                Task { @MainActor [weak owner] in
                    guard owner?.activeQueue === queue else { return }
                    owner?.activeQueue = nil
                    owner?.isGenerating = false
                    owner?.reloadSelectedProject()
                    if summary.cancelled {
                        owner?.status = "已暂停，完成的段落都已保存"
                    } else if summary.failed > 0 {
                        owner?.status = "有一段生成失败；再次点击生成会从这里继续"
                    } else {
                        owner?.status = "全文生成完成，可以制作 WAV、M4A 和 MP3 成品"
                    }
                }
            } catch {
                Task { @MainActor [weak owner] in
                    guard owner?.activeQueue === queue else { return }
                    owner?.activeQueue = nil
                    owner?.isGenerating = false
                    owner?.reloadSelectedProject()
                    owner?.status = "生成失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func cancelGeneration() {
        activeQueue?.cancel()
        status = "正在安全暂停，已完成的段落会保留…"
    }

    func makeFinalAudio() {
        guard allSegmentsCompleted, let project = selectedProject else { return }
        isFinishing = true
        status = "正在统一音量、加入停顿并制作三种成品…"
        let projectID = project.id
        let store = self.store
        let owner = self
        if playback.contextID == project.id { playback.stopAndUnload() }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let master = try store.resolveProjectFileURL(
                    projectID: projectID,
                    relativePath: "final/朗读成品.wav"
                )
                _ = try AudioAssembler(store: store).assemble(
                    project: project,
                    destination: master
                )
                let m4a = master.deletingPathExtension().appendingPathExtension("m4a")
                let mp3 = master.deletingPathExtension().appendingPathExtension("mp3")
                let exporter = AudioExporter()
                try exporter.export(wav: master, to: m4a, format: .m4a)
                try exporter.export(wav: master, to: mp3, format: .mp3)

                var updated = project
                updated.exports = [
                    NarrationExportRecord(format: "wav", relativePath: "final/朗读成品.wav"),
                    NarrationExportRecord(format: "m4a", relativePath: "final/朗读成品.m4a"),
                    NarrationExportRecord(format: "mp3", relativePath: "final/朗读成品.mp3"),
                ]
                updated.updatedAt = Date()
                try store.save(updated)
                Task { @MainActor [weak owner] in
                    owner?.isFinishing = false
                    owner?.selectedProject = updated
                    owner?.finalAudioURLs = [.wav: master, .m4a: m4a, .mp3: mp3]
                    owner?.reloadProjects(selecting: projectID)
                    owner?.status = "三种成品已制作完成，可播放或在访达中查看"
                }
            } catch {
                Task { @MainActor [weak owner] in
                    owner?.isFinishing = false
                    owner?.status = "成品制作失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func playSegment(_ segment: NarrationSegment) {
        guard let project = selectedProject,
              let selectedID = segment.selectedCandidateID,
              let candidate = segment.candidates.first(where: { $0.id == selectedID }),
              let url = try? store.resolveProjectFileURL(
                projectID: project.id,
                relativePath: candidate.relativePath
              ) else { return }
        do {
            try playback.play(
                url: url,
                title: "第 \(segment.order + 1) 段 · \(segment.kind.label)",
                contextID: project.id,
                initialRate: segment.speedFactor
            )
            status = String(format: "正在按成品语速 %.1f× 播放第 %d 段", segment.speedFactor, segment.order + 1)
        } catch {
            status = "播放失败：\(error.localizedDescription)"
        }
    }

    func playFinal(_ format: AudioExportFormat = .m4a) {
        guard let url = finalAudioURLs[format] ?? finalAudioURLs[.wav] else { return }
        guard let project = selectedProject else { return }
        do {
            try playback.play(url: url, title: "朗读成品", contextID: project.id)
            status = "正在播放朗读成品"
        } catch {
            status = "播放失败：\(error.localizedDescription)"
        }
    }

    func revealFinal() {
        guard let url = finalAudioURLs[.m4a] ?? finalAudioURLs[.wav] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func deleteProject(_ project: NarrationProject, defaultVoiceID: String) {
        do {
            try store.deleteProject(id: project.id)
            if selectedProject?.id == project.id {
                startNewProject(defaultVoiceID: defaultVoiceID)
            }
            reloadProjects()
            status = "项目已移到废纸篓"
        } catch {
            status = "项目删除失败：\(error.localizedDescription)"
        }
    }

    private func resolvedName() -> String {
        let clean = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }
        let firstLine = draftText.split(whereSeparator: { $0.isNewline }).first.map(String.init)
            ?? "未命名朗读"
        return String(firstLine.prefix(24))
    }

    private func merge(
        analyzed: [NarrationSegment],
        with existing: [NarrationSegment],
        voiceID: String
    ) -> [NarrationSegment] {
        let oldByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        return analyzed.map { fresh in
            guard var previous = oldByID[fresh.id], previous.text == fresh.text else {
                return fresh
            }
            previous.order = fresh.order
            previous.kind = fresh.kind
            previous.refreshFingerprint(voiceID: voiceID, invalidateChanged: true)
            return previous
        }
    }

    private func reloadProjects(selecting projectID: String? = nil) {
        do {
            projects = try store.loadAllProjects()
            if let projectID,
               let refreshed = projects.first(where: { $0.id == projectID }) {
                selectedProject = try store.loadProject(id: refreshed.id)
            }
        } catch {
            status = "项目列表载入失败：\(error.localizedDescription)"
        }
    }

    private func reloadSelectedProject() {
        guard let id = selectedProject?.id else { return }
        do {
            let reloaded = try store.loadProject(id: id)
            selectedProject = reloaded
            reloadProjects(selecting: id)
        } catch {
            status = "项目状态刷新失败：\(error.localizedDescription)"
        }
    }

    private func loadFinalURLs(from project: NarrationProject) {
        var urls: [AudioExportFormat: URL] = [:]
        guard !project.segments.isEmpty,
              project.segments.allSatisfy({ segment in
                  segment.generationState == .completed
                      && segment.candidates.contains(where: {
                          $0.id == segment.selectedCandidateID
                              && $0.inputFingerprint == segment.inputFingerprint
                      })
              }) else {
            finalAudioURLs = [:]
            return
        }
        for item in project.exports {
            guard let format = AudioExportFormat(rawValue: item.format),
                  let url = try? store.resolveProjectFileURL(
                    projectID: project.id,
                    relativePath: item.relativePath
                  ),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            urls[format] = url
        }
        finalAudioURLs = urls
    }

    private func refreshDraftAudioAvailability() {
        guard let project = selectedProject else { return }
        let draftMatchesSavedAudio = draftText == project.sourceText
            && draftVoiceID == project.voiceID
        if draftMatchesSavedAudio {
            loadFinalURLs(from: project)
        } else {
            finalAudioURLs = [:]
            if playback.contextID == project.id { playback.stopAndUnload() }
            status = "文章或音色已经修改，请重新分析并保存后再制作成品"
        }
    }

    private func pauseSeconds(_ pause: NarrationPause) -> Double {
        switch pause {
        case .short: return 0.25
        case .normal: return 0.55
        case .long: return 0.9
        }
    }
}
