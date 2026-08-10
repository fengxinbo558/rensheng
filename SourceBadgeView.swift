import SwiftUI

struct SourceBadgeView: View {
    let kind: NarrationSourceKind

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .accessibilityLabel("来源：\(label)")
    }

    private var label: String {
        switch kind {
        case .text: return "文字"
        case .webPage: return "网页"
        case .pdf: return "PDF"
        case .audio: return "音频"
        case .video: return "视频"
        }
    }

    private var icon: String {
        switch kind {
        case .text: return "text.alignleft"
        case .webPage: return "link"
        case .pdf: return "doc.richtext"
        case .audio: return "waveform"
        case .video: return "film"
        }
    }

    private var foreground: Color {
        switch kind {
        case .text: return Color(red: 0.17, green: 0.35, blue: 0.63)
        case .webPage: return Color(red: 0.08, green: 0.43, blue: 0.42)
        case .pdf: return Color(red: 0.63, green: 0.25, blue: 0.22)
        case .audio, .video: return Color(red: 0.42, green: 0.28, blue: 0.62)
        }
    }

    private var background: Color { foreground.opacity(0.11) }
}
