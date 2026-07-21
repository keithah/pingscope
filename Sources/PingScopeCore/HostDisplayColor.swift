import Foundation

public struct HostDisplayColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var validatedComponents: HostDisplayColor? {
        guard red.isFinite, green.isFinite, blue.isFinite,
              (0...1).contains(red), (0...1).contains(green), (0...1).contains(blue) else {
            return nil
        }
        return self
    }
}

public enum HostDisplayColorAppearance: Sendable {
    case light
    case dark
}

public enum HostDisplayColorAutomaticPalette {
    public struct RGB: Equatable, Hashable, Sendable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public var components: HostDisplayColor {
            HostDisplayColor(
                red: Double(red) / 255,
                green: Double(green) / 255,
                blue: Double(blue) / 255
            )
        }
    }

    public enum ColorToken: Int, CaseIterable, Equatable, Hashable, Sendable {
        case cobalt
        case magenta
        case teal
        case violet
        case gold
        case orange
        case seaGreen
        case purple
        case azure
        case crimson
        case olive
        case bronze

        public var lightRGB: RGB {
            switch self {
            case .cobalt: RGB(red: 0x00, green: 0x68, blue: 0xD9)
            case .magenta: RGB(red: 0xD9, green: 0x1D, blue: 0x5B)
            case .teal: RGB(red: 0x00, green: 0x8C, blue: 0x78)
            case .violet: RGB(red: 0x6D, green: 0x28, blue: 0xD9)
            case .gold: RGB(red: 0xB7, green: 0x79, blue: 0x00)
            case .orange: RGB(red: 0xD9, green: 0x5F, blue: 0x00)
            case .seaGreen: RGB(red: 0x00, green: 0x83, blue: 0x5D)
            case .purple: RGB(red: 0x8C, green: 0x22, blue: 0xC7)
            case .azure: RGB(red: 0x00, green: 0x77, blue: 0xB6)
            case .crimson: RGB(red: 0xC9, green: 0x1E, blue: 0x3A)
            case .olive: RGB(red: 0x56, green: 0x8A, blue: 0x00)
            case .bronze: RGB(red: 0xA8, green: 0x5D, blue: 0x00)
            }
        }

        public var darkRGB: RGB {
            switch self {
            case .cobalt: RGB(red: 0x27, green: 0x8D, blue: 0xFF)
            case .magenta: RGB(red: 0xFF, green: 0x3D, blue: 0x7F)
            case .teal: RGB(red: 0x00, green: 0xD1, blue: 0xB2)
            case .violet: RGB(red: 0x9B, green: 0x6C, blue: 0xFF)
            case .gold: RGB(red: 0xFF, green: 0xC4, blue: 0x00)
            case .orange: RGB(red: 0xFF, green: 0x8A, blue: 0x00)
            case .seaGreen: RGB(red: 0x00, green: 0xC8, blue: 0x96)
            case .purple: RGB(red: 0xC5, green: 0x4C, blue: 0xFF)
            case .azure: RGB(red: 0x00, green: 0xB8, blue: 0xF5)
            case .crimson: RGB(red: 0xFF, green: 0x45, blue: 0x60)
            case .olive: RGB(red: 0x8F, green: 0xD4, blue: 0x00)
            case .bronze: RGB(red: 0xEF, green: 0xA3, blue: 0x3A)
            }
        }

        public func components(for appearance: HostDisplayColorAppearance) -> HostDisplayColor {
            switch appearance {
            case .light: lightRGB.components
            case .dark: darkRGB.components
            }
        }
    }

    public static let count = ColorToken.allCases.count

    public static func color(at index: Int) -> ColorToken {
        let normalized = ((index % count) + count) % count
        return ColorToken.allCases[normalized]
    }

    public static func color(for hostID: UUID) -> ColorToken {
        color(at: stableIndex(for: hostID, paletteCount: count))
    }

    public static func stableIndex(for hostID: UUID, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        let bytes = hostID.uuid
        let value = [
            bytes.0, bytes.1, bytes.2, bytes.3,
            bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11,
            bytes.12, bytes.13, bytes.14, bytes.15
        ].reduce(UInt64.zero) { partialResult, byte in
            (partialResult &* 31) &+ UInt64(byte)
        }
        return Int(value % UInt64(paletteCount))
    }
}

public enum ResolvedHostDisplayColor: Equatable, Hashable, Sendable {
    case custom(HostDisplayColor)
    case automatic(HostDisplayColorAutomaticPalette.ColorToken)

    public init(hostID: UUID, displayColor: HostDisplayColor?) {
        if let custom = displayColor?.validatedComponents {
            self = .custom(custom)
        } else {
            self = .automatic(HostDisplayColorAutomaticPalette.color(for: hostID))
        }
    }

    public func components(for appearance: HostDisplayColorAppearance) -> HostDisplayColor {
        switch self {
        case .custom(let custom): custom
        case .automatic(let token): token.components(for: appearance)
        }
    }
}
