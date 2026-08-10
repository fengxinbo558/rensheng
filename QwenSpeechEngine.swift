import Darwin
import Foundation

final class QwenSpeechEngine: SpeechEngine, @unchecked Sendable {
    let displayName = "自然人声"
    let resources: QwenRuntimeResources

    private let stateLock = NSLock()
    private let synthesisLock = NSLock()
    private var worker: QwenWorkerConnection?
    private var cancellationRequested = false

    init(resources: QwenRuntimeResources = RuntimeLocator.qwen) {
        self.resources = resources
    }

    deinit {
        shutdownWorker()
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

        synthesisLock.lock()
        defer { synthesisLock.unlock() }
        try throwIfCancelled()
        progress(.preparing)

        let connection = try ensureWorker(progress: progress)
        let requestID = UUID().uuidString
        let referenceAudio = request.voice.synthesisReferenceAudioURL
        do {
            try connection.send([
                "command": "synthesize",
                "requestId": requestID,
                "referenceAudio": referenceAudio.path,
                "referenceText": request.voice.referenceText,
                "text": request.text,
                "output": request.outputURL.path,
                "seed": request.seed,
            ])

            while let event = try connection.readEvent() {
                try throwIfCancelled()
                guard event["requestId"] as? String == requestID else { continue }
                let name = event["event"] as? String ?? ""
                switch name {
                case "voice_prepared", "voice_reused":
                    progress(.preparing)
                case "first_audio":
                    progress(.generating(completedChunks: 1))
                case "progress":
                    progress(.generating(completedChunks: event["chunks"] as? Int))
                case "postprocessing":
                    progress(.postProcessing)
                case "completed":
                    guard FileManager.default.fileExists(atPath: request.outputURL.path) else {
                        throw SpeechEngineError.missingOutput
                    }
                    return SpeechSynthesisResult(outputURL: request.outputURL, warning: nil)
                case "failed":
                    let detail = event["error"] as? String ?? "本地语音 Worker 返回未知错误"
                    throw SpeechEngineError.generationFailed(detail)
                case "worker_stopped":
                    throw SpeechEngineError.generationFailed("本地语音 Worker 提前停止")
                default:
                    continue
                }
            }
            try throwIfCancelled()
            throw SpeechEngineError.generationFailed(
                connection.lastErrorLine ?? "本地语音 Worker 意外退出"
            )
        } catch {
            if !connection.isRunning || isCancelled {
                discardWorker(connection)
            }
            if isCancelled { throw SpeechEngineError.cancelled }
            throw error
        }
    }

    func cancel() {
        stateLock.lock()
        cancellationRequested = true
        let connection = worker
        worker = nil
        stateLock.unlock()
        connection?.terminate()
    }

    private func ensureWorker(
        progress: @escaping (SpeechEngineProgress) -> Void
    ) throws -> QwenWorkerConnection {
        try throwIfCancelled()

        stateLock.lock()
        if let existing = worker, existing.isRunning {
            stateLock.unlock()
            return existing
        }
        worker = nil
        stateLock.unlock()

        let connection = try QwenWorkerConnection.start(resources: resources)
        do {
            var isReady = false
            while let event = try connection.readEvent() {
                switch event["event"] as? String {
                case "loading", "model_loaded":
                    progress(.preparing)
                case "worker_ready":
                    isReady = true
                case "failed":
                    throw SpeechEngineError.generationFailed(
                        event["error"] as? String ?? "本地语音 Worker 启动失败"
                    )
                default:
                    continue
                }
                if isReady { break }
            }
            guard isReady else {
                throw SpeechEngineError.generationFailed(
                    connection.lastErrorLine ?? "本地语音 Worker 启动后没有响应"
                )
            }
            progress(.preparing)
            try throwIfCancelled()
        } catch {
            connection.terminate()
            throw error
        }

        stateLock.lock()
        if cancellationRequested {
            stateLock.unlock()
            connection.terminate()
            throw SpeechEngineError.cancelled
        }
        worker = connection
        stateLock.unlock()
        return connection
    }

    private func shutdownWorker() {
        stateLock.lock()
        let connection = worker
        worker = nil
        stateLock.unlock()
        connection?.shutdown()
    }

    private func discardWorker(_ connection: QwenWorkerConnection) {
        stateLock.lock()
        if worker === connection { worker = nil }
        stateLock.unlock()
        connection.terminate()
    }

    private var isCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancellationRequested
    }

    private func throwIfCancelled() throws {
        if isCancelled { throw SpeechEngineError.cancelled }
    }
}

private final class QwenWorkerConnection: @unchecked Sendable {
    let process: Process
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let errorHandle: FileHandle
    private let errorLogURL: URL
    private let ioLock = NSLock()
    private var pendingOutput = Data()
    private var closed = false

    private init(
        process: Process,
        inputHandle: FileHandle,
        outputHandle: FileHandle,
        errorHandle: FileHandle,
        errorLogURL: URL
    ) {
        self.process = process
        self.inputHandle = inputHandle
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
        self.errorLogURL = errorLogURL
    }

    deinit {
        closeHandlesAndLog()
    }

    static func start(resources: QwenRuntimeResources) throws -> QwenWorkerConnection {
        let process = Process()
        process.executableURL = resources.python
        process.arguments = [
            resources.runner.path,
            "--worker",
            "--model-dir", resources.model.path,
            "--deepfilter-model", resources.deepFilterModel.path,
            "--deepfilter-wet", "0.0",
            "--streaming-interval", "2",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PYTHONNOUSERSITE"] = "1"
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        process.environment = environment

        let standardInput = Pipe()
        let standardOutput = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput

        let errorLogURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen-worker-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: errorLogURL.path, contents: nil) else {
            throw SpeechEngineError.generationFailed("无法创建本地语音诊断文件")
        }
        let errorHandle = try FileHandle(forWritingTo: errorLogURL)
        process.standardError = errorHandle

        let connection = QwenWorkerConnection(
            process: process,
            inputHandle: standardInput.fileHandleForWriting,
            outputHandle: standardOutput.fileHandleForReading,
            errorHandle: errorHandle,
            errorLogURL: errorLogURL
        )
        do {
            try process.run()
            return connection
        } catch {
            connection.closeHandlesAndLog()
            throw error
        }
    }

    var isRunning: Bool { process.isRunning }

    var lastErrorLine: String? {
        try? errorHandle.synchronize()
        guard let data = try? Data(contentsOf: errorLogURL),
              let contents = String(data: data, encoding: .utf8) else { return nil }
        return contents
            .split(separator: "\n")
            .reversed()
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func send(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw SpeechEngineError.generationFailed("本地语音请求格式无效")
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        ioLock.lock()
        defer { ioLock.unlock() }
        guard !closed, process.isRunning else {
            throw SpeechEngineError.generationFailed(
                lastErrorLine ?? "本地语音 Worker 已停止"
            )
        }
        try inputHandle.write(contentsOf: data)
    }

    func readEvent() throws -> [String: Any]? {
        while true {
            if let newline = pendingOutput.firstIndex(of: 0x0A) {
                let line = pendingOutput[..<newline]
                pendingOutput.removeSubrange(...newline)
                if line.isEmpty { continue }
                guard let object = try JSONSerialization.jsonObject(with: Data(line))
                    as? [String: Any] else {
                    throw SpeechEngineError.generationFailed("本地语音 Worker 返回了无效数据")
                }
                return object
            }
            let next = outputHandle.availableData
            if next.isEmpty {
                if pendingOutput.isEmpty { return nil }
                let trailing = pendingOutput
                pendingOutput.removeAll(keepingCapacity: false)
                guard let object = try JSONSerialization.jsonObject(with: trailing)
                    as? [String: Any] else {
                    throw SpeechEngineError.generationFailed("本地语音 Worker 返回了无效尾数据")
                }
                return object
            }
            pendingOutput.append(next)
        }
    }

    func shutdown() {
        guard isRunning else {
            closeHandlesAndLog()
            return
        }
        let requestID = UUID().uuidString
        do {
            try send(["command": "shutdown", "requestId": requestID])
            if !waitForExit(seconds: 2.0) {
                terminate()
                return
            }
        } catch {
            terminate()
            return
        }
        closeHandlesAndLog()
    }

    func terminate() {
        if process.isRunning { process.terminate() }
        if !waitForExit(seconds: 2.0), process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
        closeHandlesAndLog()
    }

    private func waitForExit(seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        return !process.isRunning
    }

    private func closeHandlesAndLog() {
        ioLock.lock()
        guard !closed else {
            ioLock.unlock()
            return
        }
        closed = true
        ioLock.unlock()
        try? inputHandle.close()
        try? outputHandle.close()
        try? errorHandle.close()
        try? FileManager.default.removeItem(at: errorLogURL)
    }
}
