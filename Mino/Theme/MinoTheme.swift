import SwiftUI

enum MinoTheme {
    // MARK: - Colors

    static let accent = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.08)
    static let userBubble = Color.accentColor

    // Semantic surface colors
    static let agentBubble = Color.clear
    static let surfaceRaised = Color.primary.opacity(0.03)
    static let border = Color.primary.opacity(0.06)
    static let borderSubtle = Color.primary.opacity(0.03)

    // MARK: - Spacing

    static let messageSpacing: CGFloat = 6
    static let bubblePaddingH: CGFloat = 12
    static let bubblePaddingV: CGFloat = 8
    static let cornerRadius: CGFloat = 12
    static let cornerRadiusSmall: CGFloat = 8

    // MARK: - Typography

    static let bodySize: CGFloat = 13.5
    static let codeSize: CGFloat = 12.5

    // MARK: - Agent Avatar Colors

    static func avatarColor(for name: String) -> Color {
        let palettes: [Color] = [
            Color(hex: 0x8E8E93),  // system gray
            Color(hex: 0x6E7B8B),  // steel
            Color(hex: 0x7A8B8B),  // cadet
            Color(hex: 0x8B7D6B),  // wheat
            Color(hex: 0x7B8F8B),  // sage
            Color(hex: 0x8B7B8B),  // mauve
            Color(hex: 0x6B7B8B),  // slate
        ]
        let hash = abs(name.hashValue)
        return palettes[hash % palettes.count]
    }
}

// MARK: - Color Hex Init

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
