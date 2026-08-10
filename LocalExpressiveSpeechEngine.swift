import Foundation

final class LocalExpressiveSpeechEngine: SpeechEngine, @unchecked Sendable {
    let displayName = "自然情绪人声"
    let resources: ExpressiveRuntimeResources

    private let lock = NSLock()
    private var activeProcess: Process?
    private var cancellationRequested = false

    init(resources: ExpressiveRuntimeResources = RuntimeLocator.expressive) {
        self.resources = resources
    }

    var isAvailable: Bool {
        guard #available(macOS 15.0, *) else { return false }
        return resources.isAvailable
    }

    var unavailableReason: String? {
        guard #available(macOS 15.0, *) else {
            return "情绪人声需要 macOS 15 或更高版本；应用不会要求或执行系统升级"
        }
        let missing = resources.missingComponents
        return missing.isEmpty ? nil : missing.joined(separator: "、")
    }

    func synthesize(
        request: SpeechSynthesisRequest,
        progress: @escaping (SpeechEngineProgress) -> Void
    ) throws -> SpeechSynthesisResult {
        guard isAvailable else {
            throw SpeechEngineError.unavailable(unavailableReason ?? "资源不完整")
        }
        progress(.preparing)

        let process = Process()
        process.executableURL = resources.executable
        process.arguments = [
            "--model-dir", resources.model.path,
            "--campp-dir", resources.speakerModel.path,
            "--reference-audio", request.voice.synthesisReferenceAudioURL.path,
            "--reference-text", request.voice.referenceText,
            "--text", request.text,
            "--instruction", EmotionInstructionBuilder.instruction(
                expression: request.expression,
                intensity: request.expressionIntensity
            ),
            "--output", request.outputURL.path,
            "--seed", String(request.seed),
        ]
        process.currentDirectoryURL = resources.executable.deletingLastPathComponent()

        let standardOutput = Pipe()
        process.standardOutput = standardOutput
        let errorLog = FileManager.default.temporaryDirectory
            .appendingPathComponent("expressive-error-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errorLog.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorLog)
        process.standardError = errorHandle
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorLog)
        }

        try start(process)
        defer { clearActive(process) }
        readEvents(from: standardOutput.fileHandleForReading, progress: progress)
        process.waitUntilExit()
        try? errorHandle.synchronize()

        if wasCancelled { throw SpeechEngineError.cancelled }
        guard process.terminationStatus == 0 else {
            throw SpeechEngineError.generationFailed(
                readUserFacingError(from: errorLog)
                    ?? "情绪人声引擎退出码 \(process.terminationStatus)"
            )
        }
        guard FileManager.default.fileExists(atPath: request.outputURL.path) else {
            throw SpeechEngineError.missingOutput
        }
        return SpeechSynthesisResult(outputURL: request.outputURL, warning: nil)
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let process = activeProcess
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }

    private var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    private func start(_ process: Process) throws {
        lock.lock()
        let cancelledBeforeStart = cancellationRequested
        lock.unlock()
        if cancelledBeforeStart { throw SpeechEngineError.cancelled }
        try process.run()

        lock.lock()
        if cancellationRequested {
            lock.unlock()
            if process.isRunning { process.terminate() }
        } else {
            activeProcess = process
            lock.unlock()
        }
    }

    private func clearActive(_ process: Process) {
        lock.lock()
        if activeProcess === process { activeProcess = nil }
        lock.unlock()
    }

    private func readEvents(
        from handle: FileHandle,
        progress: @escaping (SpeechEngineProgress) -> Void
    ) {
        var pending = Data()
        while true {
            let next = handle.availableData
            if next.isEmpty { break }
            pending.append(next)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[..<newline]
                pending.removeSubrange(...newline)
                handleEvent(Data(line), progress: progress)
            }
        }
        if !pending.isEmpty { handleEvent(pending, progress: progress) }
    }

    private func handleEvent(
        _ data: Data,
        progress: @escaping (SpeechEngineProgress) -> Void
    ) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String else { return }
        switch event {
        case "validated", "model_progress", "speaker_model_progress", "model_loaded":
            progress(.preparing)
        case "voice_profile_ready":
            progress(.generating(completedChunks: nil))
        case "completed":
            progress(.postProcessing)
        default:
            break
        }
    }

    private func readUserFacingError(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8) else { return nil }
        for line in contents.split(separator: "\n").reversed() {
            if let data = String(line).data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = object["message"] as? String {
                return String(message.prefix(240))
            }
        }
        return contents
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.contains("error") || $0.contains("Error") })?
            .prefix(240)
            .description
    }
}
