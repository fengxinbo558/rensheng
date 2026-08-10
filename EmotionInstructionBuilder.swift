import Foundation

enum EmotionInstructionBuilder {
    static let promptVersion = "cosyvoice3-zh-v2-conversational"

    static func instruction(
        expression: NarrationExpression,
        intensity: ExpressionIntensity
    ) -> String {
        let current = expression.currentValue
        let identity = "请始终保持参考录音中同一个人的音色与身份。"
        if current == .natural {
            return "像面对熟悉的人正常说话，语速、音高和力度接近参考录音，不要播音、朗诵或表演。\(identity)"
        }

        let prefix: String
        switch intensity {
        case .subtle: prefix = "只带一点情绪，"
        case .clear: prefix = "情绪清楚但不过度，"
        case .strong: prefix = "情绪更强一些，但仍像真实对话，"
        }

        let direction: String
        switch current {
        case .happy:
            direction = "保持日常对话，只让人听出心情不错，声音略微轻松，不要刻意笑、不要广告腔或舞台腔"
        case .excited:
            direction = "保持日常对话，只比平时更有精神，语速和重音只略微变化，不要喊叫、不要夸大重音或故意加速"
        case .sad:
            direction = "像在日常谈话中克制住失落，声音略微低沉、停顿自然，不要哭腔、拖腔或故意压嗓"
        case .angry:
            direction = "表达冷静而明确的不满，只在关键词上略微加重，不要吼叫、咬牙、压嗓或制造压迫性的表演感"
        case .natural, .friendly, .steady, .emphasized:
            direction = "像面对熟悉的人正常说话，不要播音、朗诵或表演"
        }
        return "\(prefix)\(direction)。\(identity)"
    }
}
