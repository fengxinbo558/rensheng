import Foundation

private enum SpokenDirectorTestFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self { case .assertion(let message): return message }
    }
}

private func spokenExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw SpokenDirectorTestFailure.assertion(message) }
}

@main
struct SpokenScriptDirectorSelfTest {
    static func main() throws {
        let source = """
        # 产品说明

        **版本** v2.1 将在 2026年8月10日发布，价格是 99.5 元，成功率为 98%。但是，不会上传用户数据。

        1. 支持 M1、M2 和 M3。
        """
        let director = RuleSpokenScriptDirector()
        let first = try director.prepare(sourceText: source, mode: .spoken)
        let second = try director.prepare(sourceText: source, mode: .spoken)
        try spokenExpect(first.appliedMode == .spoken, "安全输入不应回退逐字朗读")
        try spokenExpect(first.version == "rule-zh-v1", "口语规则版本不正确")
        try spokenExpect(!first.outline.isEmpty, "没有生成提纲")
        try spokenExpect(first.segments.map(\.id) == second.segments.map(\.id), "同一输入的段落 ID 不稳定")
        try spokenExpect(
            first.segments.allSatisfy {
                !$0.spokenText.isEmpty
                    && $0.spokenText.count <= SpokenScriptValidator.preferredMaximumCharacters
            },
            "口语段落没有按短句整理"
        )
        let spoken = first.segments.map(\.spokenText).joined()
        let skeleton = SpokenScriptValidator().semanticSkeleton
        try spokenExpect(skeleton(source) == skeleton(spoken), "口语整理改变了原文用词")
        try spokenExpect(!spoken.contains("#"), "Markdown 标题符号不应交给 TTS")
        try spokenExpect(!spoken.contains("*"), "Markdown 强调符号不应交给 TTS")
        try spokenExpect(spoken.contains("v2.1"), "英文版本号丢失")
        try spokenExpect(spoken.contains("2026年8月10日"), "日期丢失")
        try spokenExpect(spoken.contains("98%"), "百分比丢失")
        try spokenExpect(spoken.contains("1，支持"), "编号列表没有转成可朗读停连")

        let verbatim = try director.prepare(sourceText: source, mode: .verbatim)
        try spokenExpect(verbatim.appliedMode == .verbatim, "逐字朗读模式被改变")
        try spokenExpect(
            skeleton(source) == skeleton(verbatim.segments.map(\.spokenText).joined()),
            "逐字朗读丢失内容"
        )

        let longSource = String(repeating: "这是一段需要自然停连但不能改写事实的普通话内容，", count: 8) + "到这里结束。"
        let longResult = try director.prepare(sourceText: longSource, mode: .spoken)
        try spokenExpect(longResult.segments.count > 1, "长句没有拆成多个口语片段")
        try spokenExpect(
            longResult.segments.allSatisfy {
                $0.spokenText.count <= SpokenScriptValidator.preferredMaximumCharacters
            },
            "长句拆分仍超过优先上限"
        )
        let longVerbatim = try director.prepare(sourceText: longSource, mode: .verbatim)
        try spokenExpect(
            longResult.segments.count > longVerbatim.segments.count,
            "自然讲解应比逐字朗读采用更短的停连片段"
        )

        print("SpokenScriptDirectorSelfTest: PASS")
    }
}
