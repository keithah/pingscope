import AppKit
import SwiftUI

@MainActor
struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Created By")
                    .font(.headline)

                AboutLinkRow(
                    systemImage: "person.crop.circle.fill",
                    title: "Keith Herrington",
                    subtitle: "@keithah",
                    url: Self.creatorURL
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Links")
                    .font(.headline)

                AboutLinkRow(
                    systemImage: "star",
                    title: "Star on GitHub",
                    subtitle: nil,
                    url: Self.repoURL
                )

                AboutLinkRow(
                    systemImage: "exclamationmark.triangle",
                    title: "Report Issue",
                    subtitle: nil,
                    url: Self.issuesURL
                )

                AboutLinkRow(
                    systemImage: "envelope",
                    title: "Send Feedback",
                    subtitle: nil,
                    url: Self.feedbackURL
                )
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 520, height: 560)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 84, height: 84)

            Text(Self.appName)
                .font(.system(size: 28, weight: .bold))

            Text("Version \(Self.appVersion)")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.open(Self.releasesURL)
            } label: {
                Label("Check for Updates", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "PingScope"
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "0.0.0"
    }

    private static let repoURL = URL(string: "https://github.com/keithah/pingscope")!
    private static let releasesURL = URL(string: "https://github.com/keithah/pingscope/releases")!
    private static let issuesURL = URL(string: "https://github.com/keithah/pingscope/issues/new/choose")!
    private static let feedbackURL = URL(string: "https://github.com/keithah/pingscope/issues/new/choose")!
    private static let creatorURL = URL(string: "https://github.com/keithah")!
}

private struct AboutLinkRow: View {
    let systemImage: String
    let title: String
    let subtitle: String?
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
