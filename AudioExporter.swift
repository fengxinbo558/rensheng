import Foundation

enum AudioExportFormat: String, CaseIterable, Identifiable {
    case wav
    case m4a
    case mp3

    var id: String { rawValue }
    var fileExtension: String { rawValue }
}

final class AudioExporter {
    private let mp3Encoder: URL

    init(mp3Encoder: URL = AudioExporter.defaultMP3Encoder) {
        self.mp3Encoder = mp3Encoder
    }

    func export(wav source: URL, to destination: URL, format: AudioExportFormat) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw AudioExporterError.missingSource
        }
        guard destination.pathExtension.lowercased() == format.fileExtension else {
            throw AudioExporterError.wrongFileExtension
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".export-\(UUID().uuidString).\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: temporary) }

        switch format {
        case .wav:
            try FileManager.default.copyItem(at: source, to: temporary)
        case .m4a:
            try convert(
                source: source,
                destination: temporary,
                fileFormat: "m4af",
                dataFormat: "aac "
            )
        case .mp3:
            try encodeMP3(source: source, destination: temporary)
        }

        guard FileManager.default.fileExists(atPath: temporary.path),
              (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
            throw AudioExporterError.invalidOutput
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private func encodeMP3(source: URL, destination: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: mp3Encoder.path) else {
            throw AudioExporterError.mp3EncoderMissing
        }
        let process = Process()
        process.executableURL = mp3Encoder
        process.arguments = [
            "--silent",
            "--preset", "standard",
            source.path,
            destination.path,
        ]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let details = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AudioExporterError.conversionFailed(
                details?.isEmpty == false ? details! : "MP3 编码没有完成"
            )
        }
    }

#if PORTABLE_RUNTIME
    private static let sourceDirectory = URL(fileURLWithPath: "/", isDirectory: true)
#else
    private static let sourceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
#endif

    private static var defaultMP3Encoder: URL {
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("MP3Encoder/lame")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        return sourceDirectory.appendingPathComponent("Runtime/MP3Encoder/lame")
    }

    private func convert(
        source: URL,
        destination: URL,
        fileFormat: String,
        dataFormat: String
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            source.path,
            "-o", destination.path,
            "-f", fileFormat,
            "-d", dataFormat,
            "-b", "192000",
        ]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let details = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AudioExporterError.conversionFailed(
                details?.isEmpty == false ? details! : "系统音频转换没有完成"
            )
        }
    }
}

enum AudioExporterError: LocalizedError {
    case missingSource
    case wrongFileExtension
    case conversionFailed(String)
    case mp3EncoderMissing
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .missingSource:
            return "没有找到要导出的 WAV 母版"
        case .wrongFileExtension:
            return "导出格式与文件扩展名不一致"
        case .conversionFailed(let details):
            return "音频导出失败：\(details)"
        case .mp3EncoderMissing:
            return "应用的 MP3 导出组件不完整"
        case .invalidOutput:
            return "导出完成，但文件没有通过完整性检查"
        }
    }
}
