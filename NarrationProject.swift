import Foundation

enum NarrationSourceKind: String, Codable, CaseIterable, Identifiable {
    case text
    case webPage
    case pdf
    case audio
    case video

    var id: String { rawValue }
}

struct NarrationSource: Codable, Hashable {
    var kind: NarrationSourceKind
    var title: String
    var originalURLString: String?
    var managedFileRelativePath: String?
    var importedAt: Date

    init(
        kind: NarrationSourceKind,
        title: String,
        originalURLString: String? = nil,
        managedFileRelativePath: String? = nil,
        importedAt: Date = Date()
    ) {
        self.kind = kind
        self.title = title
        self.originalURLString = originalURLString
        self.managedFileRelativePath = managedFileRelativePath
        self.importedAt = importedAt
    }
}

enum NarrationImportState: String, Codable {
    case captured
    case extracting
    case ready
    case needsAttention
}

enum NarrationScriptMode: String, Codable, CaseIterable, Identifiable {
    case spoken
    case verbatim

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spoken: return "自然讲解"
        case .verbatim: return "逐字朗读"
        }
    }

    var helpText: String {
        switch self {
        case .spoken: return "整理停连和短句，原文始终保留"
        case .verbatim: return "保持原文表达，只做安全分段"
        }
    }
}

enum NarrationScriptState: String, Codable {
    case pending
    case preparing
    case completed
    case failed
    case fallback
}

struct NarrationOutlineItem: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var sourceText: String
}

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
    static let currentFormatVersion = 5
    static let maximumCharacterCount = 30_000

    var formatVersion: Int
    let id: String
    var name: String
    var sourceText: String
    var source: NarrationSource
    var importState: NarrationImportState
    var importErrorSummary: String?
    var playbackPositionSeconds: TimeInterval
    var lastPlayedAt: Date?
    var listeningCompleted: Bool
    var voiceID: String
    var scriptMode: NarrationScriptMode
    var scriptVersion: String
    var outline: [NarrationOutlineItem]
    var scriptState: NarrationScriptState
    var scriptErrorSummary: String?
    let createdAt: Date
    var updatedAt: Date
    var segments: [NarrationSegment]
    var exports: [NarrationExportRecord]

    init(
        id: String = UUID().uuidString,
        name: String,
        sourceText: String,
        source: NarrationSource? = nil,
        importState: NarrationImportState = .ready,
        importErrorSummary: String? = nil,
        playbackPositionSeconds: TimeInterval = 0,
        lastPlayedAt: Date? = nil,
        listeningCompleted: Bool = false,
        voiceID: String,
        scriptMode: NarrationScriptMode = .spoken,
        scriptVersion: String = RuleSpokenScriptDirector.currentVersion,
        outline: [NarrationOutlineItem] = [],
        scriptState: NarrationScriptState = .pending,
        scriptErrorSummary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        segments: [NarrationSegment] = [],
        exports: [NarrationExportRecord] = []
    ) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        self.name = name
        self.sourceText = sourceText
        self.source = source ?? NarrationSource(kind: .text, title: name, importedAt: createdAt)
        self.importState = importState
        self.importErrorSummary = importErrorSummary
        self.playbackPositionSeconds = max(0, playbackPositionSeconds)
        self.lastPlayedAt = lastPlayedAt
        self.listeningCompleted = listeningCompleted
        self.voiceID = voiceID
        self.scriptMode = scriptMode
        self.scriptVersion = scriptVersion
        self.outline = outline
        self.scriptState = scriptState
        self.scriptErrorSummary = scriptErrorSummary
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

    func needsSpokenScriptRefresh(currentVersion: String) -> Bool {
        scriptMode == .spoken
            && scriptState != .pending
            && scriptVersion != currentVersion
    }

    func migratedToCurrentVersion() -> NarrationProject {
        var migrated = self
        let previousVersion = migrated.formatVersion
        migrated.formatVersion = Self.currentFormatVersion
        if previousVersion < 5 {
            migrated.source = NarrationSource(
                kind: .text,
                title: migrated.name,
                importedAt: migrated.createdAt
            )
            if migrated.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                migrated.importState = .needsAttention
                migrated.importErrorSummary = "这个旧项目没有可朗读的文字"
            } else {
                migrated.importState = .ready
                migrated.importErrorSummary = nil
            }
            migrated.playbackPositionSeconds = 0
            migrated.lastPlayedAt = nil
            migrated.listeningCompleted = false
        }
        migrated.playbackPositionSeconds = max(0, migrated.playbackPositionSeconds)
        if previousVersion < 4 {
            migrated.scriptMode = .verbatim
            migrated.scriptVersion = "legacy-verbatim-v1"
            migrated.scriptState = .completed
            migrated.scriptErrorSummary = nil
        }
        for index in migrated.segments.indices {
            if migrated.segments[index].sourceText.isEmpty {
                migrated.segments[index].sourceText = migrated.segments[index].spokenText
            }
            if migrated.segments[index].spokenText.isEmpty {
                migrated.segments[index].spokenText = migrated.segments[index].sourceText
            }
            if migrated.segments[index].scriptFingerprint.isEmpty || previousVersion < 4 {
                migrated.segments[index].refreshScriptFingerprint(
                    scriptVersion: migrated.scriptVersion
                )
            }
            if migrated.segments[index].inputFingerprint.isEmpty {
                migrated.segments[index].generationState = .pending
                migrated.segments[index].candidates = []
                migrated.segments[index].selectedCandidateID = nil
            }
            if previousVersion < 3 {
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
        case source, importState, importErrorSummary
        case playbackPositionSeconds, lastPlayedAt, listeningCompleted
        case scriptMode, scriptVersion, outline, scriptState, scriptErrorSummary
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
        source = try container.decodeIfPresent(NarrationSource.self, forKey: .source)
            ?? NarrationSource(kind: .text, title: name, importedAt: createdAt)
        importState = try container.decodeIfPresent(
            NarrationImportState.self,
            forKey: .importState
        ) ?? (sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .needsAttention
            : .ready)
        importErrorSummary = try container.decodeIfPresent(
            String.self,
            forKey: .importErrorSummary
        )
        playbackPositionSeconds = max(
            0,
            try container.decodeIfPresent(
                TimeInterval.self,
                forKey: .playbackPositionSeconds
            ) ?? 0
        )
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        listeningCompleted = try container.decodeIfPresent(
            Bool.self,
            forKey: .listeningCompleted
        ) ?? false
        scriptMode = try container.decodeIfPresent(
            NarrationScriptMode.self,
            forKey: .scriptMode
        ) ?? (formatVersion < 4 ? .verbatim : .spoken)
        scriptVersion = try container.decodeIfPresent(
            String.self,
            forKey: .scriptVersion
        ) ?? (formatVersion < 4 ? "legacy-verbatim-v1" : "rule-zh-v1")
        outline = try container.decodeIfPresent(
            [NarrationOutlineItem].self,
            forKey: .outline
        ) ?? []
        scriptState = try container.decodeIfPresent(
            NarrationScriptState.self,
            forKey: .scriptState
        ) ?? (formatVersion < 4 ? .completed : .pending)
        scriptErrorSummary = try container.decodeIfPresent(
            String.self,
            forKey: .scriptErrorSummary
        )
        segments = try container.decodeIfPresent([NarrationSegment].self, forKey: .segments) ?? []
        exports = try container.decodeIfPresent([NarrationExportRecord].self, forKey: .exports) ?? []
    }
}
