import Foundation

enum DeviceSynthesisPolicy {
    // 项目内资源基准记录 Qwen 路线峰值 physical footprint 约 13.48GB。
    // 因此 8GB 设备固定使用约 590MB 的 ZipVoice 兼容路线。
    static let minimumNaturalVoiceMemoryBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024

    static func supportsNaturalVoice(
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> Bool {
        physicalMemoryBytes >= minimumNaturalVoiceMemoryBytes
    }

    static func recommendedEngine(
        naturalResourcesAvailable: Bool,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> SynthesisEngineChoice {
        naturalResourcesAvailable && supportsNaturalVoice(physicalMemoryBytes: physicalMemoryBytes)
            ? .natural
            : .compatibility
    }
}
