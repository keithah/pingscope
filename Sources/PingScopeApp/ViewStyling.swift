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

/// Resolves an `NSAppearance` (as reported to a dynamic `NSColor` provider)
/// to the two-case appearance already used to key host-identity colors, so
/// every adaptive-color call site shares one definition of "is this dark".
extension NSAppearance {
    var pingScopeAppearance: HostDisplayColorAppearance {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}

extension Color {
    /// Builds a `Color` that resolves distinct RGB components per system
    /// appearance via the same dynamic `NSColor(name:)` mechanism used by
    /// host-identity colors, so static UI surfaces can adapt the same way.
    static func pingScopeAdaptive(light: HostDisplayColor, dark: HostDisplayColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let components = appearance.pingScopeAppearance == .dark ? dark : light
            return NSColor(srgbRed: components.red, green: components.green, blue: components.blue, alpha: 1)
        })
    }
}

/// A color that resolves distinct RGB components per appearance, so a surface
/// that was previously a hardcoded dark hex value (and therefore stayed dark
/// under a light system appearance) adapts correctly.
struct PingScopeAdaptiveColor: Equatable {
    let light: HostDisplayColor
    let dark: HostDisplayColor

    func components(for appearance: HostDisplayColorAppearance) -> HostDisplayColor {
        appearance == .dark ? dark : light
    }

    var swiftUIColor: Color {
        Color.pingScopeAdaptive(light: light, dark: dark)
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

    /// `PulseHealthRing`'s track. Dark matches the ring's previous hardcoded
    /// `#2c2c2e` literal exactly (opaque), so overlay/popover rings that don't
    /// pass an explicit `trackColor` stay visually unchanged in dark mode;
    /// light is a legible opaque gray instead of the same dark literal.
    static let ringTrack = PingScopeAdaptiveColor(
        light: .init(red: 0.847, green: 0.847, blue: 0.867),
        dark: .init(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 46.0 / 255.0)
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
    var trackColor: Color = PingScopeSurfaceColors.ringTrack.swiftUIColor

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

/// Click-to-copy, right-click-to-open behavior for a host address, shared by
/// every surface that displays one (overlay ring/signal modes, all-hosts
/// legend). Left click copies the bare address; the context menu offers
/// opening it as an http:// URL for hosts like a router's admin page.
enum PingScopeAddressActions {
    @discardableResult
    static func copyToClipboard(_ address: String) -> Bool {
        guard !address.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didCopy = pasteboard.setString(address, forType: .string)
        DebugLog.write("overlay address copy address=\(address) succeeded=\(didCopy)")
        return didCopy
    }

    static func open(_ address: String) {
        guard !address.isEmpty, let url = URL(string: "http://\(address)") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension Text {
    /// Renders an endpoint caption like "ICMP · 1.1.1.1" underlining only the
    /// address portion — the copyable part — never the protocol prefix.
    static func endpointCaption(_ caption: String, underliningAddress address: String) -> Text {
        guard !address.isEmpty, caption.hasSuffix(address) else { return Text(caption) }
        return Text(caption.dropLast(address.count)) + Text(address).underline()
    }
}

private struct CopyableAddressModifier: ViewModifier {
    let address: String
    @State private var copiedFeedbackGeneration = 0
    @State private var showsCopiedFeedback = false

    func body(content: Content) -> some View {
        // A real Button (not onTapGesture) so clicks win over the overlay
        // window's background-drag hit testing.
        Button {
            guard PingScopeAddressActions.copyToClipboard(address) else { return }
            copiedFeedbackGeneration += 1
            let generation = copiedFeedbackGeneration
            withAnimation(.easeIn(duration: 0.1)) { showsCopiedFeedback = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                guard generation == copiedFeedbackGeneration else { return }
                withAnimation(.easeOut(duration: 0.2)) { showsCopiedFeedback = false }
            }
        } label: {
            content
                .opacity(showsCopiedFeedback ? 0 : 1)
                .overlay(alignment: .leading) {
                    if showsCopiedFeedback {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                            Text("Copied")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy Address") {
                PingScopeAddressActions.copyToClipboard(address)
            }
            Button("Open Address") {
                PingScopeAddressActions.open(address)
            }
        }
        .help("Click to copy \"\(address)\". Right-click to copy or open it.")
        .accessibilityLabel("Address \(address)")
        .accessibilityHint("Double tap to copy. Use the context menu to open it.")
    }
}

extension View {
    /// Makes this view copy `address` to the clipboard on click, with a
    /// right-click fallback to also open it as a URL. A no-op when `address`
    /// is empty.
    func copyableAddress(_ address: String) -> some View {
        modifier(CopyableAddressModifier(address: address))
    }
}
