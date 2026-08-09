import Foundation

struct NarrationDefaults {
    let expression: NarrationExpression
    let speed: NarrationSpeed
    let pause: NarrationPause
}

enum NarrationRules {
    static func classify(_ text: String, standaloneLine: Bool) -> NarrationSegmentKind {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isTitle(clean, standaloneLine: standaloneLine) {
            return .title
        }

        let content = removingListPrefix(from: clean)
        if containsAny(content, ["是指", "指的是", "定义为", "所谓"]) {
            return .definition
        }
        if hasAnyPrefix(content, ["例如", "比如", "举例", "以此为例"]) {
            return .example
        }
        if content.hasSuffix("？") || content.hasSuffix("?")
            || hasAnyPrefix(content, ["为什么", "如何", "什么是", "是否"])
        {
            return .question
        }
        if hasAnyPrefix(content, [
            "因此", "所以", "总之", "综上", "由此可见", "需要注意", "关键是", "结论", "最后",
        ]) {
            return .conclusion
        }
        if hasAnyPrefix(content, [
            "首先", "其次", "接下来", "然后", "另一方面", "下面", "先",
        ]) {
            return .transition
        }
        return .explanation
    }

    static func defaults(for kind: NarrationSegmentKind) -> NarrationDefaults {
        switch kind {
        case .title, .conclusion:
            return NarrationDefaults(expression: .emphasized, speed: .slower, pause: .long)
        case .definition:
            return NarrationDefaults(expression: .steady, speed: .slower, pause: .normal)
        case .example:
            return NarrationDefaults(expression: .friendly, speed: .normal, pause: .normal)
        case .question:
            return NarrationDefaults(expression: .friendly, speed: .normal, pause: .short)
        case .transition:
            return NarrationDefaults(expression: .natural, speed: .normal, pause: .normal)
        case .explanation:
            return NarrationDefaults(expression: .natural, speed: .normal, pause: .normal)
        }
    }

    private static func isTitle(_ text: String, standaloneLine: Bool) -> Bool {
        guard standaloneLine, !text.isEmpty, text.count <= 30 else { return false }
        if text.hasPrefix("#") { return true }
        let sentenceEndings = CharacterSet(charactersIn: "。！？!?；;")
        return text.rangeOfCharacter(from: sentenceEndings) == nil
    }

    private static func removingListPrefix(from text: String) -> String {
        text.replacingOccurrences(
            of: #"^\s*(?:\d+[\.、]|[一二三四五六七八九十]+[、\.）\)]|[-•])\s*"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func containsAny(_ text: String, _ markers: [String]) -> Bool {
        markers.contains { text.contains($0) }
    }

    private static func hasAnyPrefix(_ text: String, _ markers: [String]) -> Bool {
        markers.contains { text.hasPrefix($0) }
    }
}
