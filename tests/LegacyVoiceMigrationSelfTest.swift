import Foundation

@main
struct LegacyVoiceMigrationSelfTest {
    @MainActor
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let testRoot = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"],
              let support = environment["LOCAL_AUDIO_PROBE_APP_SUPPORT"],
              let output = environment["LOCAL_AUDIO_PROBE_OUTPUT_DIR"],
              support.hasPrefix(testRoot),
              output.hasPrefix(testRoot) else {
            throw LegacyMigrationError.invalidTestDirectories
        }

        try ProbeConfiguration.ensureDataDirectories()
        let id = "legacy-self-test-voice"
        let directory = ProbeConfiguration.voicesDirectory
            .appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyAudio = directory.appendingPathComponent("reference.wav")
        try FileManager.default.copyItem(
            at: ProbeConfiguration.defaultReferenceAudio,
            to: legacyAudio
        )

        let legacy = VoiceProfile(
            id: id,
            name: "旧版测试音色",
            referenceAudioPath: legacyAudio.path,
            originalAudioPath: nil,
            processedAudioPath: nil,
            qualitySummary: nil,
            referenceText: ProbeConfiguration.defaultReferenceText,
            createdAt: Date(),
            authorizationConfirmedAt: Date(),
            isBuiltIn: false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacy]).write(to: ProbeConfiguration.voicesIndexURL, options: .atomic)

        let library = VoiceLibrary()
        guard let migrated = library.customProfiles.first(where: { $0.id == id }) else {
            throw LegacyMigrationError.failed("迁移后没有找到旧音色")
        }
        try require(migrated.originalAudioPath != nil, "迁移后没有原始音频路径")
        try require(migrated.processedAudioPath != nil, "迁移后没有降噪音频路径")
        try require(migrated.qualitySummary != nil, "迁移后没有质量信息")
        try require(
            FileManager.default.fileExists(atPath: migrated.originalAudioPath ?? ""),
            "迁移后原始音频不存在"
        )
        try require(
            FileManager.default.fileExists(atPath: migrated.processedAudioPath ?? ""),
            "迁移后降噪音频不存在"
        )
        try require(FileManager.default.fileExists(atPath: legacyAudio.path), "迁移删除了旧版音频")

        print("LegacyVoiceMigrationSelfTest PASS")
        print("audio=\(migrated.referenceAudioPath)")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw LegacyMigrationError.failed(message) }
    }
}

enum LegacyMigrationError: LocalizedError {
    case invalidTestDirectories
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidTestDirectories:
            return "迁移自检必须使用独立临时目录"
        case .failed(let message):
            return message
        }
    }
}
