import Foundation

public enum DownloadError: Error, LocalizedError {
    case offlineCacheMiss(String)

    public var errorDescription: String? {
        switch self {
        case .offlineCacheMiss(let message): return message
        }
    }
}

/// Offline-only replacement used by the isolated benchmark build.
/// Model files are prepared by `download_local_models.sh`; inference never
/// performs an implicit network request.
public enum HuggingFaceDownloader {
    public static let weightFileExtensions: Set<String> = [
        "safetensors", "mlmodelc", "mlpackage",
    ]

    public static func getCacheDirectory(
        for modelId: String,
        basePath: URL? = nil,
        cacheDirName: String = "emotion-models"
    ) throws -> URL {
        guard let basePath else {
            throw DownloadError.offlineCacheMiss(
                "离线基准必须明确提供项目内模型目录：\(modelId)")
        }
        return basePath.appendingPathComponent(
            modelId.replacingOccurrences(of: "/", with: "_"),
            isDirectory: true
        )
    }

    public static func weightsExist(in directory: URL) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return false }
        return entries.contains { weightFileExtensions.contains($0.pathExtension) }
    }

    public static func downloadWeights(
        modelId: String,
        to directory: URL,
        additionalFiles: [String] = [],
        offlineMode: Bool = false,
        retryDelaysSeconds: [Int]? = nil,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        _ = additionalFiles
        _ = offlineMode
        _ = retryDelaysSeconds
        guard weightsExist(in: directory) else {
            throw DownloadError.offlineCacheMiss(
                "项目内模型尚未准备：\(modelId)")
        }
        progressHandler?(1)
    }

    public static func downloadFiles(
        modelId: String,
        to directory: URL,
        files: [String],
        offlineMode: Bool = false,
        retryDelaysSeconds: [Int]? = nil,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        _ = offlineMode
        _ = retryDelaysSeconds
        for file in files where !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(file).path
        ) {
            throw DownloadError.offlineCacheMiss(
                "项目内模型文件缺失：\(modelId)/\(file)")
        }
        progressHandler?(1)
    }
}
