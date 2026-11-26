import SwiftUI

// Design tokens per the CX transformation brief's §4 palette (supersedes the spec's own
// §9.2 tokens on explicit request). Single place they're translated into SwiftUI Color so
// no view hardcodes a hex or a raw Color.green/.red.
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                   red: Double((hex >> 16) & 0xFF) / 255,
                   green: Double((hex >> 8) & 0xFF) / 255,
                   blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    static let bgBase = Color(hex: 0x090C10)
    static let bgSurface = Color(hex: 0x10151C)
    static let bgElevated = Color(hex: 0x171E27)
    static let borderSubtle = Color(hex: 0x26313D)
    static let textPrimary = Color(hex: 0xE6EDF3)
    static let textSecondary = Color(hex: 0x8492A6)
    static let bull = Color(hex: 0x2DD4A0)
    static let bear = Color(hex: 0xF05D83)
    static let accent = Color(hex: 0x60A5FA)
    static let warn = Color(hex: 0xF5B942)
}
