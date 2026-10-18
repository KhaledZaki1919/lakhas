import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Design tokens for direction A, "Tahini & Mint" (docs/design.md). Views use these, never literals.
public enum Theme {
    public enum Palette {
        public static let bg = Color(light: 0xFBF7F0, dark: 0x171412)
        public static let surface = Color(light: 0xFFFFFF, dark: 0x221E1B)
        public static let surfaceSunken = Color(light: 0xF4EEE4, dark: 0x1D1A17)
        public static let ink = Color(light: 0x2A2420, dark: 0xF3EDE4)
        public static let muted = Color(light: 0x6B6158, dark: 0xA89E93)
        public static let line = Color(light: 0xE6DCCC, dark: 0x332D28)
        public static let track = Color(light: 0xEFE7DA, dark: 0x3A332D)

        public static let primary = Color(light: 0x1F7A5A, dark: 0x5CC59B)
        public static let onPrimary = Color(light: 0xFFFFFF, dark: 0x0E1F18)
        public static let halo = Color(light: 0xEAD9BA, dark: 0x4A3F30)
        public static let accent = Color(light: 0xB4363F, dark: 0xF07A80)
        public static let success = primary
        public static let warning = Color(light: 0x9A6200, dark: 0xF0B54A)

        public static let protein = Color(light: 0x2F6FB0, dark: 0x6FA8E6)
        public static let carbs = Color(light: 0xA86F0E, dark: 0xE7B44F)
        public static let fat = Color(light: 0x8A5BB8, dark: 0xB993E3)

        // Dish placeholder plates (docs/design.md §1.4), with mint (`primary`) and pomegranate (`accent`).
        public static let plateOlive = Color(light: 0x6B7A3A, dark: 0xA9B86E)
        public static let plateEggplant = Color(light: 0x4B2E4F, dark: 0xC79BCB)
        public static let plateWheat = Color(light: 0x8F6410, dark: 0xE3B65A)
        public static let plateTahini = Color(light: 0x7E6236, dark: 0xD9BF8F)
    }

    public enum Space {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let screenMargin: CGFloat = 16
    }

    public enum Radius {
        public static let card: CGFloat = 20
        public static let control: CGFloat = 14
    }
}

extension Color {
    /// A color that follows light/dark appearance. Hex values are 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(rgbHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgbHex: isDark ? dark : light)
        })
        #endif
    }
}

/// One 8-bit channel of a 0xRRGGBB value as 0...1.
private func channel(_ hex: UInt32, shift: UInt32) -> CGFloat {
    CGFloat((hex >> shift) & 0xFF) / 255
}

#if canImport(UIKit)
extension UIColor {
    convenience init(rgbHex: UInt32) {
        self.init(
            red: channel(rgbHex, shift: 16), green: channel(rgbHex, shift: 8), blue: channel(rgbHex, shift: 0), alpha: 1
        )
    }
}
#elseif canImport(AppKit)
extension NSColor {
    convenience init(rgbHex: UInt32) {
        self.init(
            srgbRed: channel(rgbHex, shift: 16), green: channel(rgbHex, shift: 8), blue: channel(rgbHex, shift: 0), alpha: 1
        )
    }
}
#endif
