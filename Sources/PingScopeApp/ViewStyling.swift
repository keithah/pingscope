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
    var trackColor: Color = Color(hex: "#2c2c2e")

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
