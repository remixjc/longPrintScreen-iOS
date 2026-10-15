import SwiftUI

enum Theme {
    static let background = Color(red: 0.035, green: 0.038, blue: 0.065)
    static let card = Color(red: 0.09, green: 0.095, blue: 0.13)
    static let inset = Color(red: 0.13, green: 0.135, blue: 0.18)
    static let muted = Color(red: 0.59, green: 0.60, blue: 0.68)
    static let green = Color(red: 0.65, green: 0.94, blue: 0.44)
    static let purple = Color(red: 0.65, green: 0.52, blue: 1)
    static let cyan = Color(red: 0.36, green: 0.85, blue: 0.88)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.045)))
    }
}

struct PrimaryButton: ButtonStyle {
    var color: Color = Theme.green
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(Theme.background)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 18))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SectionLabel: View {
    let title: String
    let detail: String
    var body: some View {
        HStack {
            Text(title).font(.system(size: 20, weight: .bold))
            Spacer()
            Text(detail).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

struct ProBadge: View {
    var body: some View {
        Text("PRO").font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1).foregroundStyle(Theme.purple)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Theme.purple.opacity(0.14), in: Capsule())
    }
}
