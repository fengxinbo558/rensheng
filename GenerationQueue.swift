import Foundation

final class GenerationQueue: @unchecked Sendable {
    typealias OutputValidator = @Sendable (URL) throws -> TimeInterval
    typealias ProgressHandler = @Sendable (GenerationQueueProgress) -> Void

    private let store: ProjectStore
    private let engine: SpeechEngine
    private let outputValidator: OutputValidator
    private let lock = NSLock()
    private var running = false
    private var cancellationRequested = false
    private(set) var journal = GenerationJournal()

    init(
        store: ProjectStore,
        engine: SpeechEngine,
        outputValidator: OutputValidator? = nil
    ) {
        self.store = store
        self.engine = engine
        self.outputValidator = outputValidator ?? { url in
            let quality = try AudioProcessor.analyzeAudio(at: url)
            guard quality.duration > 0, quality.clippingFraction < 0.0001 else {
                throw GenerationQueueError.invalidAudio
            }
            return quality.duration
        }
    }

    func run(
        projectID: String,
        voice: VoiceProfile,
        progress: ProgressHandler? = nil
    ) throws -> GenerationQueueSummary {
        try beginRun()
        defer { finishRun() }
        guard engine.isAvailable else {
            throw GenerationQueueError.engineUnavailable(
                engine.unavailableReason ?? "本地语音资源未就绪"
            )
        }

        var project = try store.loadProject(id: projectID)
        if project.voiceID != voice.id {
            project.voiceID = voice.id
            project.refreshSegmentFingerprints(invalidateChanged: true)
            try store.save(project)
        }
        var summary = GenerationQueueSummary()
        let orderedIndices = project.segments.indices.sorted {
            project.segments[$0].order < project.segments[$1].order
        }
        let total = orderedIndices.count

        for (position, index) in orderedIndices.enumerated() {
            if isCancellationRequested {
                summary.cancelled = true
                break
            }

            if try canReuse(project: project, segment: project.segments[index]) {
                summary.skipped += 1
                let reusedJob = GenerationJob(
                    projectID: project.id,
                    segmentID: project.segments[index].id,
                    attempt: 0
                )
                journal.record(.reused, job: reusedJob)
                progress?(
                    GenerationQueueProgress(
                        completed: summary.completed + summary.skipped,
                        total: total,
                        currentSegment: position + 1,
                        status: "已复用第 \(position + 1) 段"
                    )
                )
                continue
            }

            project.segments[index].generationState = .generating
            project.segments[index].errorSummary = nil
            try store.save(project)
            var segmentFinished = false

            for attempt in 1...2 {
                let job = GenerationJob(
                    projectID: project.id,
                    segmentID: project.segments[index].id,
                    attempt: attempt
                )
                journal.record(.started, job: job)
                progress?(
                    GenerationQueueProgress(
                        completed: summary.completed + summary.skipped,
                        total: total,
                        currentSegment: position + 1,
                        status: attempt == 1
                            ? "正在生成第 \(position + 1) 段"
                            : "正在重试第 \(position + 1) 段"
                    )
                )
                let candidateID = UUID().uuidString
                let relativePath = "segments/\(project.segments[index].id)-\(candidateID).wav"
                let output = try store.resolveProjectFileURL(
                    projectID: project.id,
                    relativePath: relativePath
                )

                do {
                    let result = try engine.synthesize(
                        request: SpeechSynthesisRequest(
                            text: project.segments[index].text,
                            voice: voice,
                            outputURL: output,
                            zipVoiceSteps: 8
                        )
                    ) { _ in }
                    if isCancellationRequested {
                        try? FileManager.default.removeItem(at: result.outputURL)
                        throw SpeechEngineError.cancelled
                    }
                    let duration = try outputValidator(result.outputURL)
                    let candidate = NarrationAudioCandidate(
                        id: candidateID,
                        relativePath: relativePath,
                        inputFingerprint: project.segments[index].inputFingerprint,
                        engineName: engine.displayName,
                        durationSeconds: duration
                    )
                    project.segments[index].candidates.append(candidate)
                    project.segments[index].selectedCandidateID = candidate.id
                    project.segments[index].generationState = .completed
                    project.segments[index].errorSummary = result.warning
                    try store.save(project)
                    journal.record(.completed, job: job)
                    summary.completed += 1
                    segmentFinished = true
                    break
                } catch {
                    try? FileManager.default.removeItem(at: output)
                    if isCancellationRequested || isCancellationError(error) {
                        project.segments[index].generationState = .cancelled
                        project.segments[index].errorSummary = nil
                        try store.save(project)
                        journal.record(.cancelled, job: job)
                        summary.cancelled = true
                        return summary
                    }
                    if attempt == 1 {
                        journal.record(.retrying, job: job, message: concise(error))
                        continue
                    }
                    project.segments[index].generationState = .failed
                    project.segments[index].errorSummary = concise(error)
                    try store.save(project)
                    journal.record(.failed, job: job, message: concise(error))
                    summary.failed += 1
                    return summary
                }
            }

            if !segmentFinished { break }
        }
        return summary
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let shouldCancelEngine = running
        lock.unlock()
        if shouldCancelEngine { engine.cancel() }
    }

    private func beginRun() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { throw GenerationQueueError.alreadyRunning }
        running = true
        cancellationRequested = false
        journal = GenerationJournal()
    }

    private func finishRun() {
        lock.lock()
        running = false
        lock.unlock()
    }

    private var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    private func canReuse(
        project: NarrationProject,
        segment: NarrationSegment
    ) throws -> Bool {
        guard segment.generationState == .completed,
              let selectedID = segment.selectedCandidateID,
              let selected = segment.candidates.first(where: { $0.id == selectedID }),
              selected.inputFingerprint == segment.inputFingerprint else {
            return false
        }
        let url = try store.resolveProjectFileURL(
            projectID: project.id,
            relativePath: selected.relativePath
        )
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if case SpeechEngineError.cancelled = error { return true }
        return false
    }

    private func concise(_ error: Error) -> String {
        String(error.localizedDescription.prefix(180))
    }
}

enum GenerationQueueError: LocalizedError {
    case alreadyRunning
    case engineUnavailable(String)
    case invalidAudio

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "这个项目正在生成中"
        case .engineUnavailable(let reason):
            return "本地语音资源未就绪：\(reason)"
        case .invalidAudio:
            return "生成的音频没有通过完整性检查"
        }
    }
}
