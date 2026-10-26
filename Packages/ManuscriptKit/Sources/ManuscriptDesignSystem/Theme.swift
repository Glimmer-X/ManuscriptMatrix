import SwiftUI

public enum MMColor {
    public static let canvas = Color(light: 0xF5F2EC, dark: 0x111318)
    public static let surface = Color(light: 0xFFFDF9, dark: 0x1B1E25)
    public static let elevated = Color(light: 0xFFFFFF, dark: 0x232730)
    public static let ink = Color(light: 0x20232A, dark: 0xF1F0EC)
    public static let secondaryInk = Color(light: 0x6E716F, dark: 0xA9ADB7)
    public static let hairline = Color(light: 0xDED9D0, dark: 0x343945)
    public static let sidebar = Color(light: 0x1C2333, dark: 0x0B0E14)
    public static let sidebarInk = Color.white.opacity(0.94)
    public static let indigo = Color(light: 0x5066D8, dark: 0x8293F4)
    public static let indigoWash = Color(light: 0xE9ECFC, dark: 0x272D4A)
    public static let jade = Color(light: 0x21866B, dark: 0x63C6A7)
    public static let jadeWash = Color(light: 0xE4F4EE, dark: 0x183B34)
    public static let amber = Color(light: 0xB47720, dark: 0xE7AD55)
    public static let amberWash = Color(light: 0xFAEFD9, dark: 0x46351D)
    public static let vermilion = Color(light: 0xBF513F, dark: 0xEF806E)
    public static let vermilionWash = Color(light: 0xF9E7E3, dark: 0x472A27)
    public static let graphite = Color(light: 0x777B80, dark: 0x969BA5)
}

public enum MMSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}

public enum MMLayout {
    public static let sidebarWidth: CGFloat = 224
    public static let cardRadius: CGFloat = 13
}

public extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let useDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: useDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
