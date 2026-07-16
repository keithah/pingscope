#if os(iOS)
import SwiftUI

public struct PingScopeIOSOnboardingView: View {
    public let presentation: PingScopeIOSOnboardingPresentation
    public let onSelectDestination: (PingScopeIOSOnboardingPresentation.Destination) -> Void
    public let onDismiss: () -> Void

    public init(
        presentation: PingScopeIOSOnboardingPresentation,
        onSelectDestination: @escaping (PingScopeIOSOnboardingPresentation.Destination) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.onSelectDestination = onSelectDestination
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("PingScope works best when these optional capabilities match how you use the app. Nothing is requested from this checklist.")
                        .foregroundStyle(.secondary)
                }
                Section("Setup") {
                    ForEach(presentation.items) { item in
                        Button {
                            if let destination = item.destination {
                                onSelectDestination(destination)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.status == .satisfied ? "checkmark.circle.fill" : "exclamationmark.circle")
                                    .foregroundStyle(item.status == .satisfied ? .green : .orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).foregroundStyle(.primary)
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.destination != nil {
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(item.destination == nil)
                    }
                }
            }
            .navigationTitle(presentation.overallStatus == .allSet ? "You're All Set" : "Finish Setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}
#endif
