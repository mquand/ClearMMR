import Foundation
import AppKit
import UserNotifications

// Mục dọn ổ đĩa: titleKey là key localization (tiếng Việt), deleteContentsOnly
// = xóa toàn bộ con bên trong thay vì xóa cả thư mục.
struct CleanupItem: Identifiable, Sendable {
    let id = UUID()
    let titleKey: String
    let url: URL
    var bytes: UInt64 = 0
    let deleteContentsOnly: Bool

    var localizedTitle: String { NSLocalizedString(titleKey, comment: "") }
}

private func diskUsageBytes(_ url: URL) -> UInt64 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
    process.arguments = ["-sk", url.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return 0 }
    process.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let kb = Int64(out.split(separator: "\t").first ?? "") ?? 0
    return UInt64(max(0, kb)) * 1024
}

@MainActor
final class DiskCleaner: ObservableObject {
    enum State: Equatable {
        case idle, scanning, cleaning
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var items: [CleanupItem] = []
    @Published private(set) var lastFreed: UInt64?
    @Published private(set) var message: String?
    @Published private(set) var adminBytes: UInt64 = 0
    @Published private(set) var isAdminCleaning = false

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private var targets: [CleanupItem] {
        [
            CleanupItem(titleKey: "Bộ nhớ đệm ứng dụng (Caches)", url: home.appendingPathComponent("Library/Caches"), deleteContentsOnly: true),
            CleanupItem(titleKey: "Tệp log (Logs)", url: home.appendingPathComponent("Library/Logs"), deleteContentsOnly: true),
            CleanupItem(titleKey: "Thùng rác", url: home.appendingPathComponent(".Trash"), deleteContentsOnly: true),
            CleanupItem(titleKey: "Xcode DerivedData", url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"), deleteContentsOnly: false),
            CleanupItem(titleKey: "iOS DeviceSupport", url: home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"), deleteContentsOnly: false),
            CleanupItem(titleKey: "CoreSimulator Caches", url: home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"), deleteContentsOnly: true),
        ]
    }

    /// Quét dung lượng từng mục bằng `du -sk` (chạy nền, không block UI).
    func scan() async {
        state = .scanning
        items = []
        lastFreed = nil
        message = nil
        let snapshot = targets
        let scanned = await Task.detached(priority: .utility) {
            snapshot.map { item in
                var copy = item
                copy.bytes = diskUsageBytes(item.url)
                return copy
            }
        }.value
        items = scanned.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        state = .idle
        if items.isEmpty {
            message = NSLocalizedString("Không tìm thấy mục nào để dọn.", comment: "")
        }
    }

    /// Xóa các mục đã quét (chạy nền).
    func clean() async {
        guard !items.isEmpty else { return }
        state = .cleaning
        let snapshot = items
        items = []
        let freed = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            var total: UInt64 = 0
            for item in snapshot {
                do {
                    if item.deleteContentsOnly {
                        let children = try fm.contentsOfDirectory(
                            at: item.url, includingPropertiesForKeys: nil
                        )
                        for child in children {
                            try? fm.removeItem(at: child)
                        }
                    } else {
                        try fm.removeItem(at: item.url)
                    }
                    total += item.bytes
                } catch {
                    // Bỏ qua mục không xóa được (permissions, file đang dùng)
                }
            }
            return total
        }.value
        lastFreed = freed
        state = .idle
        notifyFreed(freed)
    }

    // MARK: - Deep clean (admin)

    /// Đường dẫn cấp hệ thống dọn được an toàn: cache & log sẽ tự tái tạo.
    private var adminTargets: [String] {
        ["/Library/Caches", "/Library/Logs"]
    }

    func scanAdmin() async {
        let paths = adminTargets
        adminBytes = await Task.detached(priority: .utility) {
            paths.reduce(0) { $0 + diskUsageBytes(URL(fileURLWithPath: $1)) }
        }.value
    }

    /// Xóa cache/log cấp hệ thống qua NSAppleScript admin privileges.
    func cleanAdmin() async {
        isAdminCleaning = true
        defer { isAdminCleaning = false }
        let paths = adminTargets.map { "'\($0)/'*" }.joined(separator: " ")
        let source = #"do shell script "rm -rf \#(paths) 2>/dev/null" with administrator privileges"#
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error == nil {
            notifyFreed(adminBytes)
            adminBytes = 0
        } else if let nsError = error,
                  let detail = nsError["NSAppleScriptErrorMessage"] as? String {
            message = detail
        }
    }

    private func notifyFreed(_ bytes: UInt64) {
        let gb = String(format: "%.1f", Double(bytes) / Double(1 << 30))
        let body = String(
            format: NSLocalizedString("Đã giải phóng %@ GB trên ổ đĩa.", comment: ""),
            gb
        )
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let content = UNMutableNotificationContent()
            content.title = "ClearMMR"
            content.body = body
            content.sound = .default
            try? await center.add(UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil
            ))
        }
    }
}
