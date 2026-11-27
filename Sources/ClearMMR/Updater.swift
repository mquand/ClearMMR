import Foundation
import AppKit
import CryptoKit
import UserNotifications

// Tự cập nhật qua GitHub Releases của repo gốc.
// Flow: check API -> so version -> tải zip -> verify sha256 -> giải nén
// -> thay bundle .app -> relaunch. Không cần Sparkle/private key.
@MainActor
final class AppUpdater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)   // tag mới, vd "v1.0.5"
        case downloading
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latestTag = ""

    private let repo = "mquand/ClearMMR"
    private let lastCheckKey = "lastUpdateCheck"
    private let checkInterval: TimeInterval = 24 * 3600

    init() {
        Task.detached(priority: .utility) {
            Self.cleanupOldBackups()
        }
        if let updatedVersion = UserDefaults.standard.string(forKey: "justUpdatedToVersion") {
            UserDefaults.standard.removeObject(forKey: "justUpdatedToVersion")
            let content = UNMutableNotificationContent()
            content.title = "ClearMMR"
            content.body = String(
                format: NSLocalizedString("Đã cập nhật lên phiên bản %@.", comment: ""),
                updatedVersion
            )
            let req = UNNotificationRequest(identifier: "clearmmr-updated", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Chỉ check nếu đã quá 24h kể từ lần check trước (gọi khi mở popover).
    func checkIfNeeded() {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        if Date().timeIntervalSince1970 - last > checkInterval {
            check()
        }
    }

    func check() {
        guard state != .checking, state != .downloading else { return }
        state = .checking
        Task {
            do {
                let info = try await fetchLatestRelease()
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
                latestTag = info.tag
                if isNewer(info.tag, than: currentVersion) {
                    state = .available(info.tag)
                } else {
                    state = .upToDate
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func dismiss() {
        if case .available = state { state = .idle }
        if case .upToDate = state { state = .idle }
        if case .failed = state { state = .idle }
    }

    func install() {
        guard case .available = state else { return }
        state = .downloading
        Task {
            do {
                try await downloadAndInstall()
                // không quay lại state — app sẽ terminate + relaunch
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - GitHub API

    private struct ReleaseInfo {
        let tag: String
        let zipURL: URL
        let sha256: String?
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("ClearMMR/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "ClearMMR", code: 1, userInfo: [NSLocalizedDescriptionKey: "HTTP error"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else {
            throw NSError(domain: "ClearMMR", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid release JSON"])
        }
        guard let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
              let urlString = zip["browser_download_url"] as? String,
              let url = URL(string: urlString) else {
            throw NSError(domain: "ClearMMR", code: 3, userInfo: [NSLocalizedDescriptionKey: "No .zip asset"])
        }
        var sha: String? = nil
        if let digest = zip["digest"] as? String, digest.hasPrefix("sha256:") {
            sha = String(digest.dropFirst("sha256:".count))
        }
        return ReleaseInfo(tag: tag, zipURL: url, sha256: sha)
    }

    // MARK: - Download & install

    private func downloadAndInstall() async throws {
        let info = try await fetchLatestRelease()

        // Chặn app translocated (chạy trực tiếp từ DMG) — không thay được bundle
        let bundlePath = Bundle.main.bundleURL.path
        guard !bundlePath.contains("AppTranslocation") else {
            throw NSError(domain: "ClearMMR", code: 4, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Hãy copy app vào Applications rồi thử lại.", comment: "")
            ])
        }

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("clearmmr-update-\(UUID().uuidString)")
        let extractDir = workDir.appendingPathComponent("extracted")
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let zipPath = workDir.appendingPathComponent("update.zip")
        let (tempURL, _) = try await URLSession.shared.download(from: info.zipURL)
        try fm.moveItem(at: tempURL, to: zipPath)

        // Verify SHA-256 nếu GitHub cung cấp digest
        if let expected = info.sha256 {
            let data = try Data(contentsOf: zipPath)
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual.lowercased() == expected.lowercased() else {
                throw NSError(domain: "ClearMMR", code: 5, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("File tải về sai checksum, đã hủy cập nhật.", comment: "")
                ])
            }
        }

        try shell("/usr/bin/ditto", ["-x", "-k", zipPath.path, extractDir.path])
        let newApp = extractDir.appendingPathComponent("ClearMMR.app")
        guard fm.fileExists(atPath: newApp.path) else {
            throw NSError(domain: "ClearMMR", code: 6, userInfo: [NSLocalizedDescriptionKey: "ClearMMR.app not found in zip"])
        }

        // Gỡ quarantine cho bản mới tải về
        _ = try? shellStatus("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        // Thay thế bundle hiện tại
        let target = Bundle.main.bundleURL
        let parentDir = target.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parentDir.path) else {
            throw NSError(domain: "ClearMMR", code: 7, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Không có quyền ghi vào thư mục chứa app.", comment: "")
            ])
        }

        let backup = parentDir.appendingPathComponent("ClearMMR-old-\(UUID().uuidString).app")
        try fm.moveItem(at: target, to: backup)
        do {
            try fm.moveItem(at: newApp, to: target)
        } catch {
            try? fm.moveItem(at: backup, to: target) // rollback
            throw error
        }

        // Relaunch app mới (-n: ép instance mới, tránh attach vào process cũ)
        // rồi thoát bản cũ. Bản mới sẽ tự dọn ClearMMR-old-*.app khi khởi động.
        if !latestTag.isEmpty {
            UserDefaults.standard.set(latestTag, forKey: "justUpdatedToVersion")
        }
        _ = try? shellStatus("/usr/bin/open", ["-n", target.path])
        NSApp.terminate(nil)
    }

    /// Dọn dẹp các bản backup `ClearMMR-old-*.app` còn sót lại từ các lần update trước.
    nonisolated static func cleanupOldBackups() {
        let fm = FileManager.default
        let parentDir = Bundle.main.bundleURL.deletingLastPathComponent()
        guard let items = try? fm.contentsOfDirectory(at: parentDir, includingPropertiesForKeys: nil) else { return }
        for item in items {
            let name = item.lastPathComponent
            if name.hasPrefix("ClearMMR-old-") && name.hasSuffix(".app") {
                try? fm.removeItem(at: item)
            }
        }
    }

    // MARK: - Helpers

    private func shell(_ path: String, _ args: [String]) throws {
        let status = try shellStatus(path, args)
        guard status == 0 else {
            throw NSError(domain: "ClearMMR", code: 8, userInfo: [
                NSLocalizedDescriptionKey: "\(path) failed (\(status)): \(args.joined(separator: " "))"
            ])
        }
    }

    private func shellStatus(_ path: String, _ args: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// So sánh version "v1.2.3" vs "1.2.4" theo từng thành phần số.
    private func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.drop(while: { $0 == "v" || $0 == "V" })
                .split(separator: ".")
                .compactMap { Int($0) }
        }
        let a = parts(tag)
        let b = parts(current)
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
