import Foundation
import PingScopeCore
import SwiftUI

#if os(iOS)
public struct PingScopeIOSRootView: View {
    public var host: HostConfig
    public var session: MonitorSessionState?
    public var onStart: (MonitorSessionDuration) -> Void
    public var onStop: () -> Void

    public init(
        host: HostConfig = .defaultInternet,
        session: MonitorSessionState? = nil,
        onStart: @escaping (MonitorSessionDuration) -> Void = { _ in },
        onStop: @escaping () -> Void = {}
    ) {
        self.host = host
        self.session = session
        self.onStart = onStart
        self.onStop = onStop
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                hostSummary
                sessionSummary
                controls
                Spacer()
            }
            .padding()
            .navigationTitle("PingScope")
        }
    }

    private var hostSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(host.displayName)
                .font(.headline)
            Text("\(host.method.rawValue.uppercased()) \(host.address)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session?.duration.displayName ?? "No session")
                .font(.title2.monospacedDigit())
            Text(session?.phase().rawValue.capitalized ?? "Ready")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        HStack {
            Button("30s") {
                onStart(.thirtySeconds)
            }
            .buttonStyle(.borderedProminent)

            Button("1m") {
                onStart(.oneMinute)
            }
            .buttonStyle(.bordered)

            Button("Stop") {
                onStop()
            }
            .buttonStyle(.bordered)
            .disabled(session == nil)
        }
    }
}
#else
public enum PingScopeIOSBuildMarker {
    public static let isAvailableOnThisPlatform = false
}
#endif
