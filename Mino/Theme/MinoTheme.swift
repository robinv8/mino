import SwiftUI

enum MinoTheme {
    // MARK: - Colors

    static let accent = Color(hex: 0x7C5CFC)
    static let accentSoft = Color(hex: 0x7C5CFC).opacity(0.12)
    static let userBubbleGradient = LinearGradient(
        colors: [Color(hex: 0x8B6CFF), Color(hex: 0x6B4CE6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Semantic surface colors
    static let agentBubble = Color(.controlBackgroundColor)
    static let surfaceRaised = Color(.controlBackgroundColor)
    static let border = Color.primary.opacity(0.08)
    static let borderSubtle = Color.primary.opacity(0.04)

    // MARK: - Spacing

    static let messageSpacing: CGFloat = 12
    static let bubblePaddingH: CGFloat = 14
    static let bubblePaddingV: CGFloat = 10
    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSmall: CGFloat = 10

    // MARK: - Shadows

    static let bubbleShadow: some ShapeStyle = Color.black.opacity(0.04)
    static let bubbleShadowRadius: CGFloat = 6

    // MARK: - Typography

    static let bodySize: CGFloat = 14
    static let codeSize: CGFloat = 13

    // MARK: - Agent Avatar Colors

    static func avatarGradient(for name: String) -> LinearGradient {
        let palettes: [(Color, Color)] = [
            (Color(hex: 0x8B6CFF), Color(hex: 0x6B4CE6)),
            (Color(hex: 0x06B6D4), Color(hex: 0x0891B2)),
            (Color(hex: 0xF59E0B), Color(hex: 0xD97706)),
            (Color(hex: 0xEF4444), Color(hex: 0xDC2626)),
            (Color(hex: 0x10B981), Color(hex: 0x059669)),
            (Color(hex: 0xEC4899), Color(hex: 0xDB2777)),
            (Color(hex: 0x3B82F6), Color(hex: 0x2563EB)),
        ]
        let hash = abs(name.hashValue)
        let pair = palettes[hash % palettes.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
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
