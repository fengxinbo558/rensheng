import Foundation

final class QwenSpeechEngine: SpeechEngine, @unchecked Sendable {
    let displayName = "自然人声"
    let resources: QwenRuntimeResources

    private let lock = NSLock()
    private var activeProcess: Process?
    private var cancellationRequested = false

    init(resources: QwenRuntimeResources = RuntimeLocator.qwen) {
        self.resources = resources
    }

    var isAvailable: Bool { resources.isAvailable }

    var unavailableReason: String? {
        let missing = resources.missingComponents
        return missing.isEmpty ? nil : missing.joined(separator: "、")
    }

    func synthesize(
        request: SpeechSynthesisRequest,
        progress: @escaping (SpeechEngineProgress) -> Void
    ) throws -> SpeechSynthesisResult {
        guard resources.isAvailable else {
            throw SpeechEngineError.unavailable(unavailableReason ?? "资源不完整")
        }
        progress(.preparing)

        let process = Process()
        process.executableURL = resources.python
        let referenceAudio = request.voice.synthesisReferenceAudioURL
        process.arguments = [
            resources.runner.path,
            "--model-dir", resources.model.path,
            "--reference-audio", referenceAudio.path,
            "--reference-text", request.voice.referenceText,
            "--text", request.text,
            "--output", request.outputURL.path,
            "--deepfilter-model", resources.deepFilterModel.path,
            "--deepfilter-wet", "0.0",
            "--streaming-interval", "2",
            "--seed", String(request.seed),
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PYTHONNOUSERSITE"] = "1"
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        process.environment = environment

        let standardOutput = Pipe()
        process.standardOutput = standardOutput
        let errorLog = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen-error-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errorLog.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorLog)
        process.standardError = errorHandle
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorLog)
        }

        try start(process)
        defer { clearActive(process) }
        readEvents(
            from: standardOutput.fileHandleForReading,
            progress: progress
        )
        process.waitUntilExit()
        try? errorHandle.synchronize()

        if wasCancelled {
            throw SpeechEngineError.cancelled
        }
        guard process.terminationStatus == 0 else {
            throw SpeechEngineError.generationFailed(
                readUserFacingError(from: errorLog)
                    ?? "自然人声引擎退出码 \(process.terminationStatus)"
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
        if process?.isRunning == true {
            process?.terminate()
        }
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
        if cancelledBeforeStart {
            throw SpeechEngineError.cancelled
        }

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
        if !pending.isEmpty {
            handleEvent(pending, progress: progress)
        }
    }

    private func handleEvent(
        _ data: Data,
        progress: @escaping (SpeechEngineProgress) -> Void
    ) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String else { return }
        switch event {
        case "loading", "model_loaded":
            progress(.preparing)
        case "first_audio":
            progress(.generating(completedChunks: 1))
        case "progress":
            progress(.generating(completedChunks: object["chunks"] as? Int))
        case "postprocessing":
            progress(.postProcessing)
        default:
            break
        }
    }

    private func readUserFacingError(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8) else { return nil }
        return contents
            .split(separator: "\n")
            .reversed()
            .map(String.init)
            .first(where: { $0.hasPrefix("error:") })?
            .replacingOccurrences(of: "error:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
