import Foundation

struct SpokenScriptSegment: Identifiable, Hashable {
    let id: String
    let order: Int
    let sourceText: String
    let spokenText: String
    let speakerRole: NarrationSpeakerRole
}

struct SpokenScriptResult: Hashable {
    let requestedMode: NarrationScriptMode
    let appliedMode: NarrationScriptMode
    let version: String
    let outline: [NarrationOutlineItem]
    let segments: [SpokenScriptSegment]
    let usedFallback: Bool
    let warning: String?
}

protocol SpokenScriptDirecting {
    var version: String { get }
    func prepare(sourceText: String, mode: NarrationScriptMode) throws -> SpokenScriptResult
}

struct RuleSpokenScriptDirector: SpokenScriptDirecting {
    let version = "rule-zh-v1"
    private let validator = SpokenScriptValidator()

    func prepare(sourceText: String, mode: NarrationScriptMode) throws -> SpokenScriptResult {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpokenScriptDirectorError.emptyText }
        guard sourceText.count <= NarrationProject.maximumCharacterCount else {
            throw SpokenScriptDirectorError.textTooLong
        }

        do {
            let prepared = makeSegments(sourceText: sourceText, mode: mode)
            try validator.validate(
                sourceText: sourceText,
                segments: prepared,
                requiresExactWording: true,
                maximumCharacters: mode == .spoken ? 70 : 120
            )
            return SpokenScriptResult(
                requestedMode: mode,
                appliedMode: mode,
                version: version,
                outline: makeOutline(sourceText),
                segments: prepared,
                usedFallback: false,
                warning: nil
            )
        } catch {
            guard mode == .spoken else { throw error }
            let fallback = makeSegments(sourceText: sourceText, mode: .verbatim)
            try validator.validate(
                sourceText: sourceText,
                segments: fallback,
                requiresExactWording: true,
                maximumCharacters: 120
            )
            return SpokenScriptResult(
                requestedMode: mode,
                appliedMode: .verbatim,
                version: "rule-verbatim-v1",
                outline: makeOutline(sourceText),
                segments: fallback,
                usedFallback: true,
                warning: "自然整理未通过保真检查，已改为逐字朗读"
            )
        }
    }

    private func makeSegments(
        sourceText: String,
        mode: NarrationScriptMode
    ) -> [SpokenScriptSegment] {
        let lines = normalizedLines(sourceText)
        let preferredMaximum = mode == .spoken
            ? SpokenScriptValidator.preferredMaximumCharacters
            : 100
        var chunks: [(source: String, spoken: String)] = []
        for line in lines {
            let sourceLine = mode == .spoken ? readableSource(line) : line
            let spokenLine = mode == .spoken ? normalizeForSpeech(sourceLine) : sourceLine
            let sourceCharacters = Array(sourceLine)
            var sourceOffset = 0
            for part in splitNaturally(spokenLine, maximum: preferredMaximum) where !part.isEmpty {
                let upper = min(sourceOffset + part.count, sourceCharacters.count)
                let sourcePart = String(sourceCharacters[sourceOffset..<upper])
                chunks.append((source: sourcePart, spoken: part))
                sourceOffset = upper
            }
        }
        return chunks.enumerated().map { order, chunk in
            SpokenScriptSegment(
                id: stableID(order: order, text: chunk.spoken),
                order: order,
                sourceText: chunk.source,
                spokenText: chunk.spoken,
                speakerRole: .narrator
            )
        }
    }

    private func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func readableSource(_ line: String) -> String {
        var result = line
        result = result.replacingOccurrences(
            of: #"^\s{0,3}#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"^\s*[-*•]\s+"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"^\s*>\s*"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"^\s*(\d+)[.)、]\s*"#,
            with: "$1.",
            options: .regularExpression
        )
        for marker in ["**", "__", "~~", "`"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeForSpeech(_ line: String) -> String {
        line
            .replacingOccurrences(
                of: #"^(\d+)[.)、]"#,
                with: "$1，",
                options: .regularExpression
            )
            .replacingOccurrences(of: ":", with: "，")
            .replacingOccurrences(of: ";", with: "；")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitNaturally(_ text: String, maximum: Int) -> [String] {
        let sentenceEndings: Set<Character> = ["。", "！", "？", "!", "?", "；", ";"]
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if sentenceEndings.contains(character) {
                sentences.append(current)
                current = ""
            }
        }
        if !current.isEmpty { sentences.append(current) }

        let pieces = sentences.flatMap { splitLongPiece($0, maximum: maximum) }
        var merged: [String] = []
        var buffer = ""
        for piece in pieces {
            if !buffer.isEmpty,
               buffer.count + piece.count > maximum {
                merged.append(buffer)
                buffer = ""
            }
            buffer += piece
        }
        if !buffer.isEmpty { merged.append(buffer) }
        return merged
    }

    private func splitLongPiece(_ text: String, maximum: Int) -> [String] {
        var remaining = Array(text)
        var results: [String] = []
        let preferredBreaks: Set<Character> = ["，", ",", "、", "：", ":"]
        while remaining.count > maximum {
            var cut = maximum
            if maximum > 20 {
                for index in stride(from: maximum - 1, through: 19, by: -1) {
                    if preferredBreaks.contains(remaining[index]) {
                        cut = index + 1
                        break
                    }
                }
            }
            results.append(String(remaining[..<cut]))
            remaining.removeFirst(cut)
        }
        if !remaining.isEmpty { results.append(String(remaining)) }
        return results
    }

    private func makeOutline(_ sourceText: String) -> [NarrationOutlineItem] {
        normalizedLines(sourceText).enumerated().map { index, line in
            let clean = normalizeForSpeech(readableSource(line))
            let title = String(clean.prefix(22)) + (clean.count > 22 ? "…" : "")
            return NarrationOutlineItem(
                id: stableID(order: index, text: line),
                title: title,
                sourceText: line
            )
        }
    }

    private func stableID(order: Int, text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(order)\u{1f}\(text)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "spoken-%03d-%016llx", order, hash)
    }
}

enum SpokenScriptDirectorError: LocalizedError {
    case emptyText
    case textTooLong

    var errorDescription: String? {
        switch self {
        case .emptyText: return "请输入要整理的普通话内容"
        case .textTooLong: return "第一版每个项目最多支持 3000 个字"
        }
    }
}
