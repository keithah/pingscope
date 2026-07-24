import AppKit
import PingScopeCore
import SwiftUI

extension Color {
    init(statusColor: StatusColor) {
        switch statusColor {
        case .gray: self = .gray
        case .green: self = .green
        case .yellow: self = .yellow
        case .red: self = .red
        }
    }

    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt64(trimmed, radix: 16), trimmed.count == 6 else {
            self = .secondary
            return
        }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self = Color(red: red, green: green, blue: blue)
    }
}

/// A color that resolves distinct RGB components per appearance, so a surface
/// that was previously a hardcoded dark hex value (and therefore stayed dark
/// under a light system appearance) adapts correctly. Mirrors the dynamic
/// `NSColor(name:)` pattern already used by `ResolvedHostDisplayColor`.
struct PingScopeAdaptiveColor: Equatable {
    struct Components: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    let light: Components
    let dark: Components

    func components(for appearance: HostDisplayColorAppearance) -> Components {
        appearance == .dark ? dark : light
    }

    var swiftUIColor: Color {
        Color(nsColor: NSColor(name: nil) { [self] appearance in
            let resolved: HostDisplayColorAppearance =
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
            let value = components(for: resolved)
            return NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: 1)
        })
    }
}

/// Adaptive surfaces for the status popover/standalone window UI. Dark values
/// match the previous hardcoded literals exactly so dark mode is visually
/// unchanged; light values are genuinely light so the UI stays legible when
/// the system appearance is light.
enum PingScopeSurfaceColors {
    static let graphCardTop = PingScopeAdaptiveColor(
        light: .init(red: 0.973, green: 0.976, blue: 0.984),
        dark: .init(red: 0, green: 0, blue: 0)
    )

    static let graphCardBottom = PingScopeAdaptiveColor(
        light: .init(red: 0.906, green: 0.925, blue: 0.957),
        dark: .init(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 39.0 / 255.0)
    )
}

extension HealthStatus {
    var statusColor: StatusColor {
        switch self {
        case .noData: .gray
        case .healthy: .green
        case .degraded: .yellow
        case .down: .red
        }
    }
}

struct PulseHealthRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat
    var trackColor: Color = Color.primary.opacity(0.12)

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct PingScopeStatusPill: View {
    let status: HealthStatus

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.16), in: Capsule())
    }

    private var color: Color {
        Color(statusColor: status.statusColor)
    }

    private var label: String {
        switch status {
        case .noData: "No Data"
        case .healthy: "Healthy"
        case .degraded: "Degraded"
        case .down: "Down"
        }
    }
}
