import Foundation

private enum EmotionInstructionTestFailure: Error {
    case assertion(String)
}

private func emotionExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw EmotionInstructionTestFailure.assertion(message) }
}

@main
struct EmotionInstructionBuilderSelfTest {
    static func main() throws {
        let natural = EmotionInstructionBuilder.instruction(
            expression: .natural,
            intensity: .strong
        )
        try emotionExpect(!natural.contains("情绪更强"), "自然档不应受强度影响")
        try emotionExpect(natural.contains("不要播音、朗诵或表演"), "自然档必须限制表演感")

        let subtle = EmotionInstructionBuilder.instruction(
            expression: .angry,
            intensity: .subtle
        )
        let clear = EmotionInstructionBuilder.instruction(
            expression: .angry,
            intensity: .clear
        )
        let strong = EmotionInstructionBuilder.instruction(
            expression: .angry,
            intensity: .strong
        )
        try emotionExpect(subtle != clear && clear != strong, "三档强度必须产生不同指令")
        try emotionExpect(subtle.contains("只带一点情绪"), "轻微档应保持微表情")
        try emotionExpect(subtle.contains("不要吼叫"), "愤怒档必须限制喊叫")
        try emotionExpect(strong.contains("仍像真实对话"), "较强档仍需保持真人对话")
        try emotionExpect(
            strong.contains("同一个人的音色与身份"),
            "所有档位都必须保护音色身份"
        )

        let migrated = EmotionInstructionBuilder.instruction(
            expression: .emphasized,
            intensity: .strong
        )
        try emotionExpect(migrated == natural, "旧版强调值应安全迁移为自然表达")
    }
}
