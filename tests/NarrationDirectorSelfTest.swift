import Foundation

private struct NarrationFixture: Decodable {
    let name: String
    let text: String
    let expectedKinds: [String]
}

private enum NarrationDirectorTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func directorExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw NarrationDirectorTestFailure.assertion(message) }
}

private func spokenCharacters(_ value: String) -> String {
    value.filter { !$0.isWhitespace }
}

@main
struct NarrationDirectorSelfTest {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let fixturePath = environment["LOCAL_AUDIO_PROBE_TEST_FIXTURES"] else {
            throw NarrationDirectorTestFailure.assertion("缺少规则测试材料")
        }
        let fixtureURL = URL(fileURLWithPath: fixturePath)
            .appendingPathComponent("narration-cases.json")
        let fixtures = try JSONDecoder().decode(
            [NarrationFixture].self,
            from: Data(contentsOf: fixtureURL)
        )
        let director = NarrationDirector()

        for fixture in fixtures {
            let first = try director.analyze(text: fixture.text, voiceID: "voice-test")
            let second = try director.analyze(text: fixture.text, voiceID: "voice-test")
            try directorExpect(
                first.map(\.kind.rawValue) == fixture.expectedKinds,
                "\(fixture.name) 的结构识别不符合预期：\(first.map(\.kind.rawValue))"
            )
            try directorExpect(first.map(\.id) == second.map(\.id), "同一文章的段落标识必须稳定")
            try directorExpect(
                spokenCharacters(first.map(\.text).joined()) == spokenCharacters(fixture.text),
                "分析不能改写用户原文"
            )
            try directorExpect(first.allSatisfy { $0.text.count <= 120 }, "单段不得超过 120 字")
        }

        let defaults = try director.analyze(
            text: "知识标题\n\n所谓缓存，是指暂时保存常用数据。\n\n例如，浏览器会缓存图片。\n\n这样做有什么好处？\n\n因此，它可以减少重复下载。",
            voiceID: "voice-test"
        )
        try directorExpect(defaults[0].expression == .natural, "标题默认不应刻意表演")
        try directorExpect(defaults[0].speedFactor == 0.9, "标题应默认0.9倍")
        try directorExpect(defaults[0].pause == .long, "标题后应长停顿")
        try directorExpect(defaults[1].expression == .natural, "定义默认应自然表达")
        try directorExpect(defaults[2].expression == .natural, "举例默认应自然表达")
        try directorExpect(defaults[3].pause == .short, "疑问后应短停顿")
        try directorExpect(defaults[4].expression == .natural, "结论默认不应刻意强调")

        let longText = String(repeating: "这是一段需要被安全拆分的普通话知识内容，", count: 16) + "到这里结束。"
        let longSegments = try director.analyze(text: longText, voiceID: "voice-test")
        try directorExpect(longSegments.count > 1, "长段落应自动拆分")
        try directorExpect(longSegments.allSatisfy { $0.text.count <= 120 }, "长段落拆分后仍超限")
        try directorExpect(
            spokenCharacters(longSegments.map(\.text).joined()) == spokenCharacters(longText),
            "拆分长段落不能丢字"
        )

        do {
            _ = try director.analyze(text: "   \n", voiceID: "voice-test")
            throw NarrationDirectorTestFailure.assertion("空文章不应通过分析")
        } catch NarrationDirectorError.emptyText {
            // 预期结果。
        }

        print("NarrationDirectorSelfTest: PASS")
    }
}
