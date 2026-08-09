import Foundation

struct NarrationExportRecord: Identifiable, Codable, Hashable {
    let id: String
    let format: String
    let relativePath: String
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        format: String,
        relativePath: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.format = format
        self.relativePath = relativePath
        self.createdAt = createdAt
    }
}

struct NarrationProject: Identifiable, Codable, Hashable {
    static let currentFormatVersion = 2
    static let maximumCharacterCount = 3_000

    var formatVersion: Int
    let id: String
    var name: String
    var sourceText: String
    var voiceID: String
    let createdAt: Date
    var updatedAt: Date
    var segments: [NarrationSegment]
    var exports: [NarrationExportRecord]

    init(
        id: String = UUID().uuidString,
        name: String,
        sourceText: String,
        voiceID: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        segments: [NarrationSegment] = [],
        exports: [NarrationExportRecord] = []
    ) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        self.name = name
        self.sourceText = sourceText
        self.voiceID = voiceID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.segments = segments
        self.exports = exports
    }

    mutating func refreshSegmentFingerprints(invalidateChanged: Bool) {
        for index in segments.indices {
            segments[index].refreshFingerprint(
                voiceID: voiceID,
                invalidateChanged: invalidateChanged
            )
        }
    }

    func migratedToCurrentVersion() -> NarrationProject {
        var migrated = self
        let previousVersion = migrated.formatVersion
        migrated.formatVersion = Self.currentFormatVersion
        for index in migrated.segments.indices {
            if migrated.segments[index].inputFingerprint.isEmpty {
                migrated.segments[index].generationState = .pending
                migrated.segments[index].candidates = []
                migrated.segments[index].selectedCandidateID = nil
            }
            if previousVersion < 2 {
                migrated.segments[index].refreshFingerprint(
                    voiceID: migrated.voiceID,
                    invalidateChanged: false
                )
                let refreshed = migrated.segments[index].inputFingerprint
                for candidateIndex in migrated.segments[index].candidates.indices {
                    migrated.segments[index].candidates[candidateIndex].inputFingerprint = refreshed
                }
            } else {
                migrated.segments[index].refreshFingerprint(
                    voiceID: migrated.voiceID,
                    invalidateChanged: true
                )
            }
        }
        return migrated
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, sourceText, voiceID, createdAt, updatedAt
        case segments, exports
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 0
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名朗读"
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
        voiceID = try container.decodeIfPresent(String.self, forKey: .voiceID) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        segments = try container.decodeIfPresent([NarrationSegment].self, forKey: .segments) ?? []
        exports = try container.decodeIfPresent([NarrationExportRecord].self, forKey: .exports) ?? []
    }
}
