import Foundation

enum AppVersion {
    static var shortVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
    }

    static var buildVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "0"
    }

    static var localizedDescription: String {
        L10n.format(
            "app.versionFormat",
            fallback: "Version %@ (Build %@)",
            shortVersion,
            buildVersion
        )
    }
}
