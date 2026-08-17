import Foundation

struct VoiceProfile: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    let referenceAudioPath: String
    let originalAudioPath: String?
    let processedAudioPath: String?
    let qualitySummary: AudioQualitySummary?
    var referenceText: String
    let createdAt: Date
    let authorizationConfirmedAt: Date?
    let isBuiltIn: Bool

    var referenceAudioURL: URL {
        URL(fileURLWithPath: processedAudioPath ?? referenceAudioPath)
    }

    var originalAudioURL: URL? {
        originalAudioPath.map { URL(fileURLWithPath: $0) }
    }

    var synthesisReferenceAudioURL: URL {
        if qualitySummary?.level == .good,
           let originalAudioURL,
           FileManager.default.fileExists(atPath: originalAudioURL.path) {
            return originalAudioURL
        }
        return referenceAudioURL
    }

    var synthesisReferenceLabel: String {
        if let originalAudioURL, synthesisReferenceAudioURL == originalAudioURL {
            return "保留原声细节"
        }
        return "已清理环境底噪"
    }
}

@MainActor
final class VoiceLibrary: ObservableObject {
    @Published private(set) var profiles: [VoiceProfile] = []
    @Published var selectedVoiceID: String {
        didSet {
            UserDefaults.standard.set(selectedVoiceID, forKey: Self.selectionKey)
        }
    }
    @Published var errorMessage: String?

    private static let selectionKey = "SelectedVoiceProfileID"
    private static let builtInFemaleID = "builtin-system-female"
    private static let builtInMaleID = "builtin-system-male"

    init() {
        selectedVoiceID = UserDefaults.standard.string(forKey: Self.selectionKey)
            ?? Self.builtInFemaleID
        load()
    }

    var selectedProfile: VoiceProfile {
        profiles.first(where: { $0.id == selectedVoiceID }) ?? Self.fallbackBuiltInProfile
    }

    var customProfiles: [VoiceProfile] {
        profiles.filter { !$0.isBuiltIn }
    }

    func load() {
        do {
            try ProbeConfiguration.ensureDataDirectories()
            let decodedCustom: [VoiceProfile]
            if FileManager.default.fileExists(atPath: ProbeConfiguration.voicesIndexURL.path) {
                let data = try Data(contentsOf: ProbeConfiguration.voicesIndexURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                decodedCustom = try decoder.decode([VoiceProfile].self, from: data)
                    .filter { !$0.isBuiltIn && FileManager.default.fileExists(atPath: $0.referenceAudioPath) }
            } else {
                decodedCustom = []
            }

            var migrationWarnings: [String] = []
            var custom: [VoiceProfile] = []
            var didMigrate = false
            for profile in decodedCustom {
                do {
                    let migrated = try migrateLegacyProfileIfNeeded(profile)
                    custom.append(migrated)
                    didMigrate = didMigrate || migrated != profile
                } catch {
                    custom.append(profile)
                    migrationWarnings.append("“\(profile.name)”暂未完成降噪：\(error.localizedDescription)")
                }
            }
            let builtIns = try Self.ensureBuiltInProfiles()
            profiles = builtIns + custom.sorted { $0.createdAt < $1.createdAt }
            if !profiles.contains(where: { $0.id == selectedVoiceID }) {
                selectedVoiceID = Self.builtInFemaleID
            }
            if didMigrate {
                try persistCustomProfiles()
            }
            errorMessage = migrationWarnings.isEmpty ? nil : migrationWarnings.joined(separator: "\n")
        } catch {
            profiles = [Self.fallbackBuiltInProfile]
            selectedVoiceID = Self.builtInFemaleID
            errorMessage = "声音库载入失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func createVoice(name: String, referenceText: String, sourceAudioURL: URL) throws -> VoiceProfile {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText = referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw VoiceLibraryError.invalidName
        }
        guard !cleanText.isEmpty else {
            throw VoiceLibraryError.invalidReferenceText
        }
        guard FileManager.default.fileExists(atPath: sourceAudioURL.path) else {
            throw VoiceLibraryError.missingAudio
        }

        try ProbeConfiguration.ensureDataDirectories()
        let id = UUID().uuidString
        let profileDirectory = ProbeConfiguration.voicesDirectory
            .appendingPathComponent(id, isDirectory: true)
        let originalAudio = profileDirectory.appendingPathComponent("reference-original.wav")
        let processedAudio = profileDirectory.appendingPathComponent("reference-clean.wav")
        try FileManager.default.createDirectory(
            at: profileDirectory,
            withIntermediateDirectories: true
        )

        do {
            try convertAudio(from: sourceAudioURL, to: originalAudio)
            let quality = try AudioProcessor.analyzePCM16WAV(at: originalAudio)
            try prepareReferenceAudio(
                from: originalAudio,
                to: processedAudio,
                in: profileDirectory
            )
            let profile = VoiceProfile(
                id: id,
                name: cleanName,
                referenceAudioPath: processedAudio.path,
                originalAudioPath: originalAudio.path,
                processedAudioPath: processedAudio.path,
                qualitySummary: quality,
                referenceText: cleanText,
                createdAt: Date(),
                authorizationConfirmedAt: Date(),
                isBuiltIn: false
            )
            profiles.append(profile)
            do {
                try persistCustomProfiles()
            } catch {
                profiles.removeAll { $0.id == profile.id }
                throw error
            }
            selectedVoiceID = profile.id
            errorMessage = nil
            return profile
        } catch {
            try? FileManager.default.removeItem(at: profileDirectory)
            throw error
        }
    }

    func deleteVoice(_ profile: VoiceProfile) throws {
        guard !profile.isBuiltIn else { return }
        let profileDirectory = URL(fileURLWithPath: profile.referenceAudioPath)
            .deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: profileDirectory.path) {
            try FileManager.default.trashItem(at: profileDirectory, resultingItemURL: nil)
        }
        profiles.removeAll { $0.id == profile.id }
        if selectedVoiceID == profile.id {
            selectedVoiceID = Self.builtInFemaleID
        }
        try persistCustomProfiles()
        errorMessage = nil
    }

    private func convertAudio(from source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            source.path,
            "-o", destination.path,
            "-f", "WAVE",
            "-d", "LEI16@24000",
            "-c", "1",
        ]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: destination.path) else {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            let details = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw VoiceLibraryError.conversionFailed(details ?? "未知音频格式")
        }
    }

    private func prepareReferenceAudio(from original: URL, to destination: URL, in directory: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: ProbeConfiguration.denoiserRuntime.path),
              FileManager.default.fileExists(atPath: ProbeConfiguration.denoiserModel.path) else {
            throw VoiceLibraryError.denoiserMissing
        }

        let denoised = directory.appendingPathComponent("reference-denoised-16k.tmp.wav")
        let converted = directory.appendingPathComponent("reference-denoised-24k.tmp.wav")
        defer {
            try? FileManager.default.removeItem(at: denoised)
            try? FileManager.default.removeItem(at: converted)
        }

        let process = Process()
        process.executableURL = ProbeConfiguration.denoiserRuntime
        process.arguments = [
            "--speech-denoiser-gtcrn-model=\(ProbeConfiguration.denoiserModel.path)",
            "--input-wav=\(original.path)",
            "--output-wav=\(denoised.path)",
            "--num-threads=2",
            "--provider=cpu",
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: denoised.path) else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let details = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw VoiceLibraryError.processingFailed(details ?? "离线降噪失败")
        }

        try convertAudio(from: denoised, to: converted)
        try AudioProcessor.normalizeReference(from: converted, to: destination)
    }

    private func migrateLegacyProfileIfNeeded(_ profile: VoiceProfile) throws -> VoiceProfile {
        if let originalPath = profile.originalAudioPath,
           let processedPath = profile.processedAudioPath,
           FileManager.default.fileExists(atPath: originalPath),
           FileManager.default.fileExists(atPath: processedPath) {
            return profile
        }

        let legacyAudio = URL(fileURLWithPath: profile.referenceAudioPath)
        let profileDirectory = legacyAudio.deletingLastPathComponent()
        let originalAudio = profileDirectory.appendingPathComponent("reference-original.wav")
        let processedAudio = profileDirectory.appendingPathComponent("reference-clean.wav")

        if !FileManager.default.fileExists(atPath: originalAudio.path) {
            try FileManager.default.copyItem(at: legacyAudio, to: originalAudio)
        }
        if !FileManager.default.fileExists(atPath: processedAudio.path) {
            try prepareReferenceAudio(
                from: originalAudio,
                to: processedAudio,
                in: profileDirectory
            )
        }
        let quality = try AudioProcessor.analyzePCM16WAV(at: originalAudio)
        return VoiceProfile(
            id: profile.id,
            name: profile.name,
            referenceAudioPath: processedAudio.path,
            originalAudioPath: originalAudio.path,
            processedAudioPath: processedAudio.path,
            qualitySummary: quality,
            referenceText: profile.referenceText,
            createdAt: profile.createdAt,
            authorizationConfirmedAt: profile.authorizationConfirmedAt,
            isBuiltIn: false
        )
    }

    private func persistCustomProfiles() throws {
        try ProbeConfiguration.ensureDataDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(customProfiles)
        try data.write(to: ProbeConfiguration.voicesIndexURL, options: .atomic)
    }

    private static let fallbackBuiltInProfile = VoiceProfile(
        id: builtInFemaleID,
        name: "系统女声",
        referenceAudioPath: ProbeConfiguration.defaultReferenceAudio.path,
        originalAudioPath: nil,
        processedAudioPath: nil,
        qualitySummary: nil,
        referenceText: ProbeConfiguration.defaultReferenceText,
        createdAt: .distantPast,
        authorizationConfirmedAt: nil,
        isBuiltIn: true
    )

    private static func ensureBuiltInProfiles() throws -> [VoiceProfile] {
        try FileManager.default.createDirectory(
            at: ProbeConfiguration.builtInVoicesDirectory,
            withIntermediateDirectories: true
        )

        let specifications: [(id: String, name: String, systemVoice: String, filename: String)] = [
            (builtInFemaleID, "系统女声", "Tingting", "system-female.wav"),
            (builtInMaleID, "系统男声", "Grandpa (中文（中国大陆）)", "system-male.wav"),
        ]

        return try specifications.map { specification in
            let output = ProbeConfiguration.builtInVoicesDirectory
                .appendingPathComponent(specification.filename)
            try ensureSystemReferenceAudio(voice: specification.systemVoice, output: output)
            return VoiceProfile(
                id: specification.id,
                name: specification.name,
                referenceAudioPath: output.path,
                originalAudioPath: nil,
                processedAudioPath: nil,
                qualitySummary: nil,
                referenceText: ProbeConfiguration.defaultReferenceText,
                createdAt: .distantPast,
                authorizationConfirmedAt: nil,
                isBuiltIn: true
            )
        }
    }

    private static func ensureSystemReferenceAudio(voice: String, output: URL) throws {
        if FileManager.default.fileExists(atPath: output.path),
           let attributes = try? FileManager.default.attributesOfItem(atPath: output.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > 44 {
            return
        }

        let temporary = output.deletingPathExtension().appendingPathExtension("aiff")
        try? FileManager.default.removeItem(at: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", temporary.path, ProbeConfiguration.defaultReferenceText]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0,
              FileManager.default.fileExists(atPath: temporary.path) else {
            throw VoiceLibraryError.systemVoiceUnavailable(voice)
        }

        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        convert.arguments = [
            temporary.path,
            "-o", output.path,
            "-f", "WAVE",
            "-d", "LEI16@24000",
            "-c", "1",
        ]
        try convert.run()
        convert.waitUntilExit()
        guard convert.terminationStatus == 0,
              FileManager.default.fileExists(atPath: output.path) else {
            throw VoiceLibraryError.systemVoiceUnavailable(voice)
        }
    }
}

enum VoiceLibraryError: LocalizedError {
    case invalidName
    case invalidReferenceText
    case missingAudio
    case conversionFailed(String)
    case denoiserMissing
    case processingFailed(String)
    case systemVoiceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "请输入音色名称"
        case .invalidReferenceText:
            return "请输入与参考音频完全一致的原文"
        case .missingAudio:
            return "没有找到参考音频文件"
        case .conversionFailed(let details):
            return "音频转换失败：\(details)"
        case .denoiserMissing:
            return "应用的本地降噪资源不完整"
        case .processingFailed(let details):
            return "音频降噪失败：\(details)"
        case .systemVoiceUnavailable(let voice):
            return "系统音色“\(voice)”不可用，请在系统语音设置中安装中文语音"
        }
    }
}
