import SwiftUI

enum StudioPalette {
    static let canvas = Color(red: 0.955, green: 0.966, blue: 0.982)
    static let sidebar = Color(red: 0.925, green: 0.944, blue: 0.970)
    static let card = Color.white
    static let softBlue = Color(red: 0.900, green: 0.936, blue: 0.985)
    static let selectedBlue = Color(red: 0.835, green: 0.895, blue: 0.985)
    static let blue = Color(red: 0.145, green: 0.405, blue: 0.835)
    static let blueDeep = Color(red: 0.105, green: 0.255, blue: 0.520)
    static let ink = Color(red: 0.105, green: 0.145, blue: 0.225)
    static let muted = Color(red: 0.350, green: 0.405, blue: 0.500)
    static let mint = Color(red: 0.865, green: 0.955, blue: 0.920)
    static let green = Color(red: 0.100, green: 0.530, blue: 0.420)
    static let line = Color(red: 0.760, green: 0.805, blue: 0.880)
}

struct StudioCardModifier: ViewModifier {
    var fill: Color = StudioPalette.card
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(StudioPalette.line.opacity(0.46), lineWidth: 1)
            }
    }
}

extension View {
    func studioCard(fill: Color = StudioPalette.card, radius: CGFloat = 16) -> some View {
        modifier(StudioCardModifier(fill: fill, radius: radius))
    }
}
