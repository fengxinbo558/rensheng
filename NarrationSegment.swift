import Foundation

enum NarrationSegmentKind: String, Codable, CaseIterable, Identifiable {
    case title
    case explanation
    case definition
    case example
    case question
    case conclusion
    case transition

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: return "标题"
        case .explanation: return "普通讲解"
        case .definition: return "定义"
        case .example: return "举例"
        case .question: return "疑问"
        case .conclusion: return "重点结论"
        case .transition: return "段落过渡"
        }
    }
}

enum NarrationExpression: String, Codable, CaseIterable, Identifiable {
    case natural
    case friendly
    case steady
    case emphasized

    var id: String { rawValue }

    var label: String {
        switch self {
        case .natural: return "自然"
        case .friendly: return "亲切"
        case .steady: return "沉稳"
        case .emphasized: return "强调"
        }
    }
}

enum NarrationSpeed: String, Codable, CaseIterable, Identifiable {
    case slower
    case normal
    case faster

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slower: return "稍慢"
        case .normal: return "正常"
        case .faster: return "稍快"
        }
    }
}

enum NarrationPause: String, Codable, CaseIterable, Identifiable {
    case short
    case normal
    case long

    var id: String { rawValue }

    var label: String {
        switch self {
        case .short: return "短"
        case .normal: return "正常"
        case .long: return "长"
        }
    }
}

enum SegmentGenerationState: String, Codable {
    case pending
    case generating
    case completed
    case failed
    case cancelled
}

struct NarrationAudioCandidate: Identifiable, Codable, Hashable {
    let id: String
    let relativePath: String
    let inputFingerprint: String
    let engineName: String
    let durationSeconds: Double
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        relativePath: String,
        inputFingerprint: String,
        engineName: String,
        durationSeconds: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.relativePath = relativePath
        self.inputFingerprint = inputFingerprint
        self.engineName = engineName
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
    }
}

struct NarrationSegment: Identifiable, Codable, Hashable {
    let id: String
    var order: Int
    var text: String
    var kind: NarrationSegmentKind
    var expression: NarrationExpression
    var speed: NarrationSpeed
    var pause: NarrationPause
    var inputFingerprint: String
    var generationState: SegmentGenerationState
    var candidates: [NarrationAudioCandidate]
    var selectedCandidateID: String?
    var errorSummary: String?

    init(
        id: String = UUID().uuidString,
        order: Int,
        text: String,
        kind: NarrationSegmentKind,
        expression: NarrationExpression = .natural,
        speed: NarrationSpeed = .normal,
        pause: NarrationPause = .normal,
        voiceID: String
    ) {
        self.id = id
        self.order = order
        self.text = text
        self.kind = kind
        self.expression = expression
        self.speed = speed
        self.pause = pause
        inputFingerprint = ""
        generationState = .pending
        candidates = []
        selectedCandidateID = nil
        errorSummary = nil
        refreshFingerprint(voiceID: voiceID, invalidateChanged: false)
    }

    mutating func refreshFingerprint(voiceID: String, invalidateChanged: Bool) {
        let refreshed = Self.makeFingerprint(
            text: text,
            kind: kind,
            expression: expression,
            speed: speed,
            pause: pause,
            voiceID: voiceID
        )
        let changed = !inputFingerprint.isEmpty && inputFingerprint != refreshed
        inputFingerprint = refreshed
        if changed && invalidateChanged {
            generationState = .pending
            candidates = []
            selectedCandidateID = nil
            errorSummary = nil
        } else if generationState == .generating {
            generationState = .pending
        }
    }

    private static func makeFingerprint(
        text: String,
        kind: NarrationSegmentKind,
        expression: NarrationExpression,
        speed: NarrationSpeed,
        pause: NarrationPause,
        voiceID: String
    ) -> String {
        let value = [
            text,
            kind.rawValue,
            expression.rawValue,
            speed.rawValue,
            pause.rawValue,
            voiceID,
        ].joined(separator: "\u{1f}")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private enum CodingKeys: String, CodingKey {
        case id, order, text, kind, expression, speed, pause, inputFingerprint
        case generationState, candidates, selectedCandidateID, errorSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        kind = try container.decodeIfPresent(NarrationSegmentKind.self, forKey: .kind)
            ?? .explanation
        expression = try container.decodeIfPresent(NarrationExpression.self, forKey: .expression)
            ?? .natural
        speed = try container.decodeIfPresent(NarrationSpeed.self, forKey: .speed) ?? .normal
        pause = try container.decodeIfPresent(NarrationPause.self, forKey: .pause) ?? .normal
        inputFingerprint = try container.decodeIfPresent(String.self, forKey: .inputFingerprint)
            ?? ""
        generationState = try container.decodeIfPresent(
            SegmentGenerationState.self,
            forKey: .generationState
        ) ?? .pending
        candidates = try container.decodeIfPresent(
            [NarrationAudioCandidate].self,
            forKey: .candidates
        ) ?? []
        selectedCandidateID = try container.decodeIfPresent(String.self, forKey: .selectedCandidateID)
        errorSummary = try container.decodeIfPresent(String.self, forKey: .errorSummary)
    }
}
