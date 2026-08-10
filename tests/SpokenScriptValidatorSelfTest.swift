import Foundation

private enum SpokenValidatorTestFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self { case .assertion(let message): return message }
    }
}

private func validatorExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw SpokenValidatorTestFailure.assertion(message) }
}

private func segment(_ text: String) -> SpokenScriptSegment {
    SpokenScriptSegment(
        id: UUID().uuidString,
        order: 0,
        sourceText: text,
        spokenText: text,
        speakerRole: .narrator
    )
}

@main
struct SpokenScriptValidatorSelfTest {
    static func main() throws {
        let validator = SpokenScriptValidator()
        let source = "版本 v2.1 的成功率为 98%，价格是 99.5 元。"
        try validator.validate(
            sourceText: source,
            segments: [segment(source)],
            requiresExactWording: true
        )

        do {
            try validator.validate(
                sourceText: source,
                segments: [segment("版本 v2.1 的成功率为 89%，价格是 99.5 元。")],
                requiresExactWording: false
            )
            throw SpokenValidatorTestFailure.assertion("数字改变没有被拒绝")
        } catch let issue as SpokenScriptValidationIssue {
            try validatorExpect(issue.kind == .protectedTokenChanged, "数字改变错误类型不正确")
        }

        do {
            try validator.validate(
                sourceText: source,
                segments: [segment(source + "（愤怒）")],
                requiresExactWording: false
            )
            throw SpokenValidatorTestFailure.assertion("新增情绪说明没有被拒绝")
        } catch let issue as SpokenScriptValidationIssue {
            try validatorExpect(issue.kind == .stageDirectionAdded, "情绪说明错误类型不正确")
        }

        do {
            try validator.validate(
                sourceText: "原文内容。",
                segments: [segment("原文结论。")],
                requiresExactWording: true
            )
            throw SpokenValidatorTestFailure.assertion("用词改变没有被拒绝")
        } catch let issue as SpokenScriptValidationIssue {
            try validatorExpect(issue.kind == .wordingChanged, "用词改变错误类型不正确")
        }

        let overlong = String(repeating: "长", count: SpokenScriptValidator.hardMaximumCharacters + 1)
        do {
            try validator.validate(
                sourceText: overlong,
                segments: [segment(overlong)],
                requiresExactWording: true
            )
            throw SpokenValidatorTestFailure.assertion("超长段落没有被拒绝")
        } catch let issue as SpokenScriptValidationIssue {
            try validatorExpect(issue.kind == .segmentTooLong, "超长段落错误类型不正确")
        }

        print("SpokenScriptValidatorSelfTest: PASS")
    }
}
