import Foundation

struct NarrationDirector {
    private let targetMaximum = 100
    private let hardMaximum = 120

    func analyze(text: String, voiceID: String) throws -> [NarrationSegment] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NarrationDirectorError.emptyText
        }
        guard text.count <= NarrationProject.maximumCharacterCount else {
            throw NarrationDirectorError.textTooLong
        }

        let lines = text.split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var analyzed: [(text: String, kind: NarrationSegmentKind)] = []

        for line in lines {
            let wholeKind = NarrationRules.classify(line, standaloneLine: true)
            if wholeKind == .title {
                analyzed.append((line, .title))
                continue
            }

            let sentences = splitSentences(line).flatMap(splitLongText)
            var lineSegments: [(text: String, kind: NarrationSegmentKind)] = []
            for sentence in sentences where !sentence.isEmpty {
                let kind = NarrationRules.classify(sentence, standaloneLine: false)
                if let last = lineSegments.last,
                   last.kind == kind,
                   last.text.count + sentence.count <= targetMaximum {
                    lineSegments[lineSegments.count - 1].text += sentence
                } else {
                    lineSegments.append((sentence, kind))
                }
            }
            analyzed.append(contentsOf: lineSegments)
        }

        return analyzed.enumerated().map { order, item in
            let defaults = NarrationRules.defaults(for: item.kind)
            return NarrationSegment(
                id: stableID(order: order, text: item.text),
                order: order,
                text: item.text,
                kind: item.kind,
                expression: defaults.expression,
                speedFactor: defaults.speedFactor,
                pause: defaults.pause,
                voiceID: voiceID
            )
        }
    }

    func analyze(script: SpokenScriptResult, voiceID: String) -> [NarrationSegment] {
        script.segments.map { item in
            let standalone = item.spokenText.count <= 28
                && !item.spokenText.contains(where: { "。！？!?；;".contains($0) })
            let kind = NarrationRules.classify(
                item.spokenText,
                standaloneLine: standalone
            )
            let defaults = NarrationRules.defaults(for: kind)
            return NarrationSegment(
                id: item.id,
                order: item.order,
                sourceText: item.sourceText,
                spokenText: item.spokenText,
                speakerRole: item.speakerRole,
                scriptVersion: script.version,
                kind: kind,
                expression: .natural,
                speedFactor: defaults.speedFactor,
                pause: defaults.pause,
                voiceID: voiceID
            )
        }
    }

    private func splitSentences(_ text: String) -> [String] {
        let sentenceEndings: Set<Character> = ["。", "！", "？", "!", "?", "；", ";"]
        var results: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if sentenceEndings.contains(character) {
                results.append(current)
                current = ""
            }
        }
        if !current.isEmpty { results.append(current) }
        return results
    }

    private func splitLongText(_ text: String) -> [String] {
        var remaining = Array(text)
        var results: [String] = []
        let preferredBreaks: Set<Character> = ["，", ",", "、", "：", ":"]

        while remaining.count > hardMaximum {
            let searchUpper = min(110, remaining.count)
            var cut = hardMaximum
            if searchUpper >= 40 {
                for index in stride(from: searchUpper - 1, through: 39, by: -1) {
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

    private func stableID(order: Int, text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(order)\u{1f}\(text)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "segment-%03d-%016llx", order, hash)
    }
}

enum NarrationDirectorError: LocalizedError {
    case emptyText
    case textTooLong

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "请输入要分析的普通话内容"
        case .textTooLong:
            return "第一版每个项目最多支持 3000 个字"
        }
    }
}
