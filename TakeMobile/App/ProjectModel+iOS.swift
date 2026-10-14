import Foundation
import ManuscriptKit

/// What the phone does with a project that the Mac does differently: every
/// project lives in the app's own container under its id, and each keeps
/// its own token.
extension ProjectModel {
    // MARK: - Remembering

    private static let lastProjectKey = "LastProjectID"

    /// Projects live under one root, so the id is enough to find one again.
    static func remember(_ url: URL) {
        UserDefaults.standard.set(url.lastPathComponent, forKey: lastProjectKey)
    }

    static func lastProjectURL() -> URL? {
        guard let id = UserDefaults.standard.string(forKey: lastProjectKey) else { return nil }
        let url = projectsRoot.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) else { return nil }
        return url
    }

    /// Where the phone keeps its projects: `Application Support/Projects/<id>`.
    static var projectsRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Projects", isDirectory: true)
    }

    // MARK: - Backup

    /// One token per project, so removing a project removes its secret.
    static func tokenItem(for url: URL) -> KeychainItem {
        KeychainItem(service: "com.siddharthnigam.take.backup", account: url.lastPathComponent)
    }

    func backupToken() -> String? {
        projectURL.flatMap { Self.tokenItem(for: $0).read() }
    }

    /// The remote, kept per project in the defaults until the project index
    /// takes it over.
    static func readRemote(for url: URL) -> String {
        UserDefaults.standard.string(forKey: remoteKey(url)) ?? ""
    }

    static func writeRemote(_ remote: String, for url: URL) {
        if remote.isEmpty {
            UserDefaults.standard.removeObject(forKey: remoteKey(url))
        } else {
            UserDefaults.standard.set(remote, forKey: remoteKey(url))
        }
    }

    private static func remoteKey(_ url: URL) -> String {
        "BackupRemote:" + url.lastPathComponent
    }
}
