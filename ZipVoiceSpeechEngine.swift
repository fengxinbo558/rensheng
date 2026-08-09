import Foundation

final class ZipVoiceSpeechEngine: SpeechEngine, @unchecked Sendable {
    let displayName = "兼容模式"
    let isAvailable = true
    let unavailableReason: String? = nil

    private let lock = NSLock()
    private var activeProcess: Process?
    private var cancellationRequested = false

    func synthesize(
        request: SpeechSynthesisRequest,
        progress: @escaping (SpeechEngineProgress) -> Void
    ) throws -> SpeechSynthesisResult {
        progress(.preparing)
        let rawOutput = request.outputURL.deletingLastPathComponent()
            .appendingPathComponent(".processing-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: rawOutput) }

        let process = Process()
        let model = ProbeConfiguration.model
        process.executableURL = ProbeConfiguration.runtime
        process.arguments = [
            "--zipvoice-encoder=\(model.appendingPathComponent("encoder.int8.onnx").path)",
            "--zipvoice-decoder=\(model.appendingPathComponent("decoder.int8.onnx").path)",
            "--zipvoice-data-dir=\(model.appendingPathComponent("espeak-ng-data").path)",
            "--zipvoice-lexicon=\(model.appendingPathComponent("lexicon.txt").path)",
            "--zipvoice-tokens=\(model.appendingPathComponent("tokens.txt").path)",
            "--zipvoice-vocoder=\(ProbeConfiguration.vocoder.path)",
            "--reference-audio=\(request.voice.referenceAudioURL.path)",
            "--reference-text=\(request.voice.referenceText)",
            "--num-steps=\(request.zipVoiceSteps)",
            "--num-threads=2",
            "--provider=cpu",
            "--output-filename=\(rawOutput.path)",
            request.text,
        ]
        let log = Pipe()
        process.standardOutput = log
        process.standardError = log
        try start(process)
        defer { clearActive(process) }

        progress(.generating(completedChunks: nil))
        process.waitUntilExit()
        let logData = log.fileHandleForReading.readDataToEndOfFile()
        if wasCancelled {
            throw SpeechEngineError.cancelled
        }
        guard process.terminationStatus == 0 else {
            let details = String(data: logData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SpeechEngineError.generationFailed(
                details?.isEmpty == false ? details! : "兼容引擎退出码 \(process.terminationStatus)"
            )
        }
        guard FileManager.default.fileExists(atPath: rawOutput.path) else {
            throw SpeechEngineError.missingOutput
        }

        progress(.postProcessing)
        var warning: String?
        do {
            try AudioProcessor.postProcessOutput(from: rawOutput, to: request.outputURL)
        } catch {
            try FileManager.default.moveItem(at: rawOutput, to: request.outputURL)
            warning = "音频整理未完成，已保留原始结果"
        }
        return SpeechSynthesisResult(outputURL: request.outputURL, warning: warning)
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
}
