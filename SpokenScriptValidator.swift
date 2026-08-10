import Foundation

struct SpokenScriptValidationIssue: Error, Hashable, LocalizedError {
    enum Kind: String, Hashable {
        case empty
        case protectedTokenChanged
        case wordingChanged
        case stageDirectionAdded
        case segmentTooLong
    }

    let kind: Kind
    let detail: String

    var errorDescription: String? { detail }
}

struct SpokenScriptValidator {
    static let preferredMaximumCharacters = 55
    static let hardMaximumCharacters = 70

    func validate(
        sourceText: String,
        segments: [SpokenScriptSegment],
        requiresExactWording: Bool,
        maximumCharacters: Int = Self.hardMaximumCharacters
    ) throws {
        let spokenText = segments.map(\.spokenText).joined()
        guard !spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpokenScriptValidationIssue(kind: .empty, detail: "口语稿不能为空")
        }
        if let long = segments.first(where: { $0.spokenText.count > maximumCharacters }) {
            throw SpokenScriptValidationIssue(
                kind: .segmentTooLong,
                detail: "第 \(long.order + 1) 段超过 \(maximumCharacters) 个字"
            )
        }

        let sourceTokens = protectedTokenCounts(in: sourceText)
        let spokenTokens = protectedTokenCounts(in: spokenText)
        guard sourceTokens == spokenTokens else {
            throw SpokenScriptValidationIssue(
                kind: .protectedTokenChanged,
                detail: "数字、日期或英文术语发生变化"
            )
        }

        if requiresExactWording,
           semanticSkeleton(sourceText) != semanticSkeleton(spokenText) {
            throw SpokenScriptValidationIssue(
                kind: .wordingChanged,
                detail: "规则整理改变了原文用词"
            )
        }

        let directions = stageDirections(in: spokenText)
        let originalDirections = stageDirections(in: sourceText)
        guard directions.subtracting(originalDirections).isEmpty else {
            throw SpokenScriptValidationIssue(
                kind: .stageDirectionAdded,
                detail: "口语稿包含新增的情绪或舞台说明"
            )
        }
    }

    func semanticSkeleton(_ text: String) -> String {
        text.lowercased().unicodeScalars.compactMap { scalar in
            if CharacterSet.letters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar) {
                return String(scalar)
            }
            return nil
        }.joined()
    }

    private func protectedTokenCounts(in text: String) -> [String: Int] {
        let pattern = #"(?i)[a-z][a-z0-9._+\-]*|\d+(?:[.,]\d+)*(?:%|％)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var counts: [String: Int] = [:]
        for match in expression.matches(in: text, range: range) {
            guard let tokenRange = Range(match.range, in: text) else { continue }
            let token = String(text[tokenRange]).lowercased()
            counts[token, default: 0] += 1
        }
        return counts
    }

    private func stageDirections(in text: String) -> Set<String> {
        let pattern = #"[\[（(【]\s*(开心|兴奋|悲伤|愤怒|生气|叹气|哭泣|笑|强调|停顿)\s*[\]）)】]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(expression.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        })
    }
}
