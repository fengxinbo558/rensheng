import Foundation

enum SynthesisEngineChoice: String, CaseIterable, Identifiable {
    case natural
    case compatibility

    var id: String { rawValue }

    var label: String {
        switch self {
        case .natural: return "自然人声（推荐）"
        case .compatibility: return "兼容模式"
        }
    }
}

struct SpeechSynthesisRequest {
    let text: String
    let voice: VoiceProfile
    let outputURL: URL
    let zipVoiceSteps: Int
}

enum SpeechEngineProgress {
    case preparing
    case generating(completedChunks: Int?)
    case postProcessing

    var statusLabel: String {
        switch self {
        case .preparing:
            return "正在准备本地人声模型…"
        case .generating(let completedChunks):
            if let completedChunks, completedChunks > 0 {
                return "正在生成本地语音 · 已完成 \(completedChunks) 个片段"
            }
            return "正在生成本地语音…"
        case .postProcessing:
            return "正在整理音频…"
        }
    }
}

struct SpeechSynthesisResult {
    let outputURL: URL
    let warning: String?
}

protocol SpeechEngine: AnyObject, Sendable {
    var displayName: String { get }
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }

    func synthesize(
        request: SpeechSynthesisRequest,
        progress: @escaping (SpeechEngineProgress) -> Void
    ) throws -> SpeechSynthesisResult
    func cancel()
}

enum SpeechEngineError: LocalizedError {
    case unavailable(String)
    case cancelled
    case generationFailed(String)
    case missingOutput

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "自然人声资源未就绪：\(reason)"
        case .cancelled:
            return "生成已取消"
        case .generationFailed(let details):
            return "本地语音生成失败：\(details)"
        case .missingOutput:
            return "本地语音生成完成，但没有找到音频文件"
        }
    }
}
