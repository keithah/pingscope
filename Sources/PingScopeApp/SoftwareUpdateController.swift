import Combine
import Foundation
import PingScopeCore

#if canImport(Sparkle) && !APPSTORE
import Sparkle
#endif

@MainActor
final class SoftwareUpdateController: ObservableObject {
    @Published private(set) var statusMessage: String
    @Published private(set) var lastCheckRequestedAt: Date?

    let feedURL: String?
    let publicKeyConfigured: Bool
    let bundleShortVersion: String
    let bundleVersion: String

    #if canImport(Sparkle) && !APPSTORE
    private let updaterController: SPUStandardUpdaterController?
    #endif

    init(bundle: Bundle = .main) {
        feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        publicKeyConfigured = Self.publicKeyIsConfigured(publicKey)
        bundleShortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        bundleVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"

        #if canImport(Sparkle) && !APPSTORE
        if Self.isConfigured(feedURL: feedURL, publicKey: publicKey) {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            statusMessage = "Automatic update checks are enabled."
        } else {
            updaterController = nil
            statusMessage = "Set SUFeedURL and SUPublicEDKey before publishing Developer ID updates."
        }
        #elseif APPSTORE
        statusMessage = ""
        #else
        statusMessage = "Update checks are unavailable in this build."
        #endif
    }

    var isAvailable: Bool {
        #if canImport(Sparkle) && !APPSTORE
        true
        #else
        false
        #endif
    }

    var canCheckForUpdates: Bool {
        #if canImport(Sparkle) && !APPSTORE
        updaterController != nil
        #else
        false
        #endif
    }

    func checkForUpdates() {
        lastCheckRequestedAt = Date()
        #if canImport(Sparkle) && !APPSTORE
        guard let updaterController else {
            statusMessage = "Software update feed is not configured for this build."
            return
        }
        statusMessage = "Update check requested."
        updaterController.checkForUpdates(nil)
        #elseif APPSTORE
        return
        #else
        statusMessage = "Update checks are unavailable in this build."
        #endif
    }

    private static func isConfigured(feedURL: String?, publicKey: String?) -> Bool {
        guard
            let feedURL,
            feedURL.hasPrefix("https://"),
            !feedURL.contains("example.com"),
            publicKeyIsConfigured(publicKey)
        else {
            return false
        }
        return true
    }

    private static func publicKeyIsConfigured(_ publicKey: String?) -> Bool {
        guard let publicKey else { return false }
        return !publicKey.isEmpty && !publicKey.contains("REPLACE_WITH")
    }
}
