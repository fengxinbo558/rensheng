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
    case happy
    case excited
    case sad
    case angry
    // 旧项目兼容值；读取时会迁移到自然表达。
    case friendly
    case steady
    case emphasized

    var id: String { rawValue }

    var label: String {
        switch self {
        case .natural: return "自然"
        case .happy: return "开心"
        case .excited: return "兴奋"
        case .sad: return "悲伤"
        case .angry: return "愤怒"
        case .friendly: return "亲切"
        case .steady: return "沉稳"
        case .emphasized: return "强调"
        }
    }

    static let userSelectableCases: [NarrationExpression] = [
        .natural, .happy, .excited, .sad, .angry,
    ]

    var currentValue: NarrationExpression {
        switch self {
        case .friendly, .steady, .emphasized: return .natural
        default: return self
        }
    }

    var supportsIntensity: Bool { currentValue != .natural }
}

enum ExpressionIntensity: String, Codable, CaseIterable, Identifiable {
    case subtle
    case clear
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .subtle: return "轻微"
        case .clear: return "自然清楚"
        case .strong: return "较强"
        }
    }
}

private enum LegacyNarrationSpeed: String, Codable {
    case slower
    case normal
    case faster

    var factor: Double {
        switch self {
        case .slower: return 0.9
        case .normal: return 1.0
        case .faster: return 1.1
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
    var inputFingerprint: String
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
    var expressionIntensity: ExpressionIntensity
    var speedFactor: Double
    var pause: NarrationPause
    var inputFingerprint: String
    var generationState: SegmentGenerationState
    var generationAttempts: Int
    var candidates: [NarrationAudioCandidate]
    var selectedCandidateID: String?
    var errorSummary: String?

    init(
        id: String = UUID().uuidString,
        order: Int,
        text: String,
        kind: NarrationSegmentKind,
        expression: NarrationExpression = .natural,
        expressionIntensity: ExpressionIntensity = .subtle,
        speedFactor: Double = 1.0,
        pause: NarrationPause = .normal,
        voiceID: String
    ) {
        self.id = id
        self.order = order
        self.text = text
        self.kind = kind
        self.expression = expression.currentValue
        self.expressionIntensity = expressionIntensity
        self.speedFactor = Self.normalizedSpeedFactor(speedFactor)
        self.pause = pause
        inputFingerprint = ""
        generationState = .pending
        generationAttempts = 0
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
            expressionIntensity: expressionIntensity,
            voiceID: voiceID
        )
        let changed = !inputFingerprint.isEmpty && inputFingerprint != refreshed
        inputFingerprint = refreshed
        if changed && invalidateChanged {
            generationState = .pending
            generationAttempts = 0
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
        expressionIntensity: ExpressionIntensity,
        voiceID: String
    ) -> String {
        let value = [
            text,
            kind.rawValue,
            expression.rawValue,
            expressionIntensity.rawValue,
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
        case id, order, text, kind, expression, expressionIntensity, speedFactor, speed, pause
        case inputFingerprint
        case generationState, generationAttempts, candidates, selectedCandidateID, errorSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        kind = try container.decodeIfPresent(NarrationSegmentKind.self, forKey: .kind)
            ?? .explanation
        expression = try container.decodeIfPresent(NarrationExpression.self, forKey: .expression)?
            .currentValue ?? .natural
        expressionIntensity = try container.decodeIfPresent(
            ExpressionIntensity.self,
            forKey: .expressionIntensity
        ) ?? .subtle
        if let storedFactor = try container.decodeIfPresent(Double.self, forKey: .speedFactor) {
            speedFactor = Self.normalizedSpeedFactor(storedFactor)
        } else {
            let legacySpeed = try container.decodeIfPresent(LegacyNarrationSpeed.self, forKey: .speed)
                ?? .normal
            speedFactor = legacySpeed.factor
        }
        pause = try container.decodeIfPresent(NarrationPause.self, forKey: .pause) ?? .normal
        inputFingerprint = try container.decodeIfPresent(String.self, forKey: .inputFingerprint)
            ?? ""
        generationState = try container.decodeIfPresent(
            SegmentGenerationState.self,
            forKey: .generationState
        ) ?? .pending
        generationAttempts = try container.decodeIfPresent(Int.self, forKey: .generationAttempts)
            ?? (generationState == .failed ? 2 : 0)
        candidates = try container.decodeIfPresent(
            [NarrationAudioCandidate].self,
            forKey: .candidates
        ) ?? []
        selectedCandidateID = try container.decodeIfPresent(String.self, forKey: .selectedCandidateID)
        errorSummary = try container.decodeIfPresent(String.self, forKey: .errorSummary)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(order, forKey: .order)
        try container.encode(text, forKey: .text)
        try container.encode(kind, forKey: .kind)
        try container.encode(expression, forKey: .expression)
        try container.encode(expressionIntensity, forKey: .expressionIntensity)
        try container.encode(Self.normalizedSpeedFactor(speedFactor), forKey: .speedFactor)
        try container.encode(pause, forKey: .pause)
        try container.encode(inputFingerprint, forKey: .inputFingerprint)
        try container.encode(generationState, forKey: .generationState)
        try container.encode(generationAttempts, forKey: .generationAttempts)
        try container.encode(candidates, forKey: .candidates)
        try container.encodeIfPresent(selectedCandidateID, forKey: .selectedCandidateID)
        try container.encodeIfPresent(errorSummary, forKey: .errorSummary)
    }

    static let minimumSpeedFactor = 0.1
    static let maximumSpeedFactor = 3.0

    static func normalizedSpeedFactor(_ value: Double) -> Double {
        let finite = value.isFinite ? value : 1.0
        let clamped = min(max(finite, minimumSpeedFactor), maximumSpeedFactor)
        return (clamped * 10).rounded() / 10
    }

    var usesExtremeSpeed: Bool {
        speedFactor < 0.6 || speedFactor > 2.0
    }
}
