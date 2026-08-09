import AudioCommon
import CosyVoiceTTS
import Darwin
import Foundation

private enum ProbeError: Error, LocalizedError {
    case invalidArguments(String)
    case invalidReference(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message),
             .invalidReference(let message),
             .invalidOutput(let message):
            return message
        }
    }
}

private struct Arguments {
    var modelID = "aufklarer/CosyVoice3-0.5B-MLX-8bit-full"
    var modelDirectory: URL?
    var camppDirectory: URL?
    var referenceAudio: URL?
    var referenceText = ""
    var text = ""
    var instruction = ""
    var output: URL?
    var seed: UInt64 = 42
    var validateOnly = false

    static func parse(_ values: [String]) throws -> Arguments {
        var arguments = Arguments()
        var index = 0
        while index < values.count {
            let value = values[index]
            if value == "--validate-only" {
                arguments.validateOnly = true
                index += 1
                continue
            }
            guard index + 1 < values.count else {
                throw ProbeError.invalidArguments("参数缺少值：\(value)")
            }
            let next = values[index + 1]
            switch value {
            case "--model-id": arguments.modelID = next
            case "--model-dir": arguments.modelDirectory = URL(fileURLWithPath: next)
            case "--campp-dir": arguments.camppDirectory = URL(fileURLWithPath: next)
            case "--reference-audio": arguments.referenceAudio = URL(fileURLWithPath: next)
            case "--reference-text": arguments.referenceText = next
            case "--text": arguments.text = next
            case "--instruction": arguments.instruction = next
            case "--output": arguments.output = URL(fileURLWithPath: next)
            case "--seed":
                guard let seed = UInt64(next) else {
                    throw ProbeError.invalidArguments("随机种子必须是非负整数")
                }
                arguments.seed = seed
            default:
                throw ProbeError.invalidArguments("未知参数：\(value)")
            }
            index += 2
        }
        try arguments.validate()
        return arguments
    }

    func validate() throws {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProbeError.invalidArguments("模型标识不能为空")
        }
        guard let modelDirectory else {
            throw ProbeError.invalidArguments("缺少 --model-dir")
        }
        guard let camppDirectory else {
            throw ProbeError.invalidArguments("缺少 --campp-dir")
        }
        guard let referenceAudio else {
            throw ProbeError.invalidArguments("缺少 --reference-audio")
        }
        guard FileManager.default.fileExists(atPath: referenceAudio.path) else {
            throw ProbeError.invalidReference("找不到参考录音")
        }
        guard !referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProbeError.invalidArguments("参考录音原文不能为空")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProbeError.invalidArguments("目标文字不能为空")
        }
        guard text.count <= 120 else {
            throw ProbeError.invalidArguments("单条基准文字不能超过 120 字")
        }
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProbeError.invalidArguments("情绪指令不能为空")
        }
        guard !instruction.contains("<|endofprompt|>") else {
            throw ProbeError.invalidArguments("情绪指令不能包含模型边界标记")
        }
        guard let output else {
            throw ProbeError.invalidArguments("缺少 --output")
        }
        guard output.pathExtension.lowercased() == "wav" else {
            throw ProbeError.invalidOutput("输出必须是 WAV 文件")
        }
        guard output.standardizedFileURL != referenceAudio.standardizedFileURL else {
            throw ProbeError.invalidOutput("输出不能覆盖参考录音")
        }
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw ProbeError.invalidOutput("输出文件已经存在，拒绝覆盖")
        }
        _ = modelDirectory
        _ = camppDirectory
    }
}

private final class EventWriter {
    private let handle: FileHandle

    init() throws {
        let duplicated = Darwin.dup(STDOUT_FILENO)
        guard duplicated >= 0 else {
            throw ProbeError.invalidOutput("无法建立生成事件通道")
        }
        handle = FileHandle(fileDescriptor: duplicated, closeOnDealloc: true)
        guard Darwin.dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
            throw ProbeError.invalidOutput("无法隔离模型日志")
        }
    }

    func emit(_ event: String, _ payload: [String: Any] = [:]) {
        var object = payload
        object["event"] = event
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        if let bytes = line.data(using: .utf8) {
            try? handle.write(contentsOf: bytes)
        }
    }
}

@main
private struct EmotionCosyProbe {
    static func main() async {
        do {
            let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
            let events = try EventWriter()
            events.emit("validated", ["modelID": arguments.modelID])
            if arguments.validateOnly { return }

            let modelDirectory = arguments.modelDirectory!
            let camppDirectory = arguments.camppDirectory!
            let referenceAudio = arguments.referenceAudio!
            let output = arguments.output!
            try FileManager.default.createDirectory(
                at: modelDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: camppDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

            let loadStarted = CFAbsoluteTimeGetCurrent()
            let model = try await CosyVoiceTTSModel.fromPretrained(
                modelId: arguments.modelID,
                cacheDir: modelDirectory,
                offlineMode: true,
                progressHandler: { progress, status in
                    events.emit("model_progress", ["progress": progress, "status": status])
                }
            )
            let speechTokenizerURL = modelDirectory.appendingPathComponent(
                "speech_tokenizer.safetensors")
            let speechTokenizer = try SpeechTokenizerModel.fromSafetensors(
                at: speechTokenizerURL)
            let campp = try await CamPlusPlusSpeaker.fromPretrained(
                cacheDir: camppDirectory,
                offlineMode: true,
                progressHandler: { progress, status in
                    events.emit("speaker_model_progress", ["progress": progress, "status": status])
                }
            )
            events.emit("model_loaded", [
                "seconds": CFAbsoluteTimeGetCurrent() - loadStarted,
            ])

            let referenceSamples = try AudioFileLoader.load(
                url: referenceAudio, targetSampleRate: 16_000)
            let referenceDuration = Double(referenceSamples.count) / 16_000.0
            guard referenceDuration >= 5, referenceDuration <= 30 else {
                throw ProbeError.invalidReference("参考录音必须在 5 到 30 秒之间")
            }
            let profileStarted = CFAbsoluteTimeGetCurrent()
            let profile = try model.extractVoiceProfile(
                audio: referenceSamples,
                sampleRate: 16_000,
                speechTokenizer: speechTokenizer,
                camppSpeaker: campp,
                referenceTranscript: arguments.referenceText
            )
            events.emit("voice_profile_ready", [
                "seconds": CFAbsoluteTimeGetCurrent() - profileStarted,
                "referenceDuration": referenceDuration,
                "promptTokens": profile.promptToken?.dim(1) ?? 0,
                "promptFrames": profile.promptFeat?.dim(2) ?? 0,
            ])

            let generationStarted = CFAbsoluteTimeGetCurrent()
            let samples = model.synthesize(
                text: arguments.text,
                voiceProfile: profile,
                language: "chinese",
                instruction: arguments.instruction,
                seed: arguments.seed,
                verbose: false
            )
            guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else {
                throw ProbeError.invalidOutput("模型没有产生有效音频")
            }
            let peak = samples.map { abs($0) }.max() ?? 0
            guard peak > 0.001, peak <= 1.05 else {
                throw ProbeError.invalidOutput("生成音频的峰值异常")
            }

            let temporary = output.deletingPathExtension()
                .appendingPathExtension("\(UUID().uuidString).tmp.wav")
            try WAVWriter.write(samples: samples, sampleRate: 24_000, to: temporary)
            try FileManager.default.moveItem(at: temporary, to: output)
            let generationSeconds = CFAbsoluteTimeGetCurrent() - generationStarted
            let duration = Double(samples.count) / 24_000.0
            events.emit("completed", [
                "duration": duration,
                "generationSeconds": generationSeconds,
                "rtf": generationSeconds / max(duration, 0.001),
                "peak": peak,
                "sampleRate": 24_000,
                "output": output.lastPathComponent,
            ])
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let object: [String: Any] = ["event": "failed", "message": message]
            if let data = try? JSONSerialization.data(withJSONObject: object),
               let line = String(data: data, encoding: .utf8) {
                FileHandle.standardError.write(Data((line + "\n").utf8))
            }
            Darwin.exit(1)
        }
    }
}
