import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var monitor: RAMMonitor
    @EnvironmentObject private var updater: AppUpdater
    @EnvironmentObject private var cleaner: DiskCleaner
    @AppStorage("warnThreshold") private var warnThreshold = 80
    @AppStorage("critThreshold") private var critThreshold = 90
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("menuBarFormat") private var menuBarFormat = "percent"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            systemStats
            Divider()
            memoryBreakdown
            Divider()
            topProcesses
            Divider()
            actions
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            monitor.setPopoverOpen(true)
            monitor.refreshLoginItemStatus()
            updater.checkIfNeeded()
        }
        .onDisappear {
            monitor.setPopoverOpen(false)
        }
        .onChange(of: updater.state) { newState in
            if case .available(let tag) = newState {
                AppAlert.show(
                    title: "Có bản cập nhật mới",
                    message: String(format: NSLocalizedString("Phiên bản %@ đã sẵn sàng. App sẽ tự tải, cài đặt và khởi động lại.", comment: ""), tag),
                    confirmTitle: "Cập nhật",
                    cancelTitle: "Để sau",
                    onConfirm: { updater.install() },
                    onCancel: { updater.dismiss() }
                )
            }
        }
        .onChange(of: cleaner.lastFreed) { freed in
            if freed != nil { monitor.refresh() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bộ nhớ đang dùng")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatGB(monitor.usedBytes)) / \(formatGB(monitor.totalBytes))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(monitor.percent.rounded()))%")
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .foregroundStyle(headerColor)
                ProgressView(value: min(monitor.percent / 100, 1))
                    .tint(headerColor)
            }
            if monitor.ramHistory.count > 1 {
                SparklineView(values: monitor.ramHistory, color: headerColor)
                    .frame(height: 18)
            }
        }
    }

    private var headerColor: Color {
        switch monitor.percent {
        case Double(critThreshold)...: return .red
        case Double(warnThreshold)..<Double(critThreshold): return .yellow
        default: return .accentColor
        }
    }

    // MARK: - System stats

    private var systemStats: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            statBox(title: "CPU", value: String(format: "%.0f%%", monitor.cpuPercent))
            statBox(title: "Swap", value: "\(formatGB(monitor.swapUsedBytes)) / \(formatGB(monitor.swapTotalBytes))")
            statBox(title: "Ổ đĩa trống", value: formatGB(monitor.diskFreeBytes))
            statBox(title: "Uptime", value: uptimeString)
            statBox(title: "Bộ nhớ", value: pressureString, color: pressureColor)
        }
    }

    private func statBox(title: LocalizedStringKey, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(color ?? .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pressureString: String {
        switch monitor.pressureLevel {
        case 4: return NSLocalizedString("Nghiêm trọng", comment: "Memory pressure: critical")
        case 2: return NSLocalizedString("Cảnh báo", comment: "Memory pressure: warning")
        default: return NSLocalizedString("Bình thường", comment: "Memory pressure: normal")
        }
    }

    private var pressureColor: Color {
        switch monitor.pressureLevel {
        case 4: return .red
        case 2: return .yellow
        default: return .green
        }
    }

    private var uptimeString: String {
        let uptime = ProcessInfo.processInfo.systemUptime
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        if hours > 0 {
            return String(format: NSLocalizedString("%lldg %lldp", comment: "Uptime: hours and minutes"), hours, minutes)
        }
        if minutes > 0 {
            return String(format: NSLocalizedString("%lldp", comment: "Uptime: minutes"), minutes)
        }
        return String(format: NSLocalizedString("%llds", comment: "Uptime: seconds"), Int(uptime))
    }

    // MARK: - Breakdown

    private var memoryBreakdown: some View {
        VStack(spacing: 6) {
            statRow("Active", monitor.activeBytes)
            statRow("Wired", monitor.wiredBytes)
            statRow("Compressed", monitor.compressedBytes)
        }
    }

    private func statRow(_ title: LocalizedStringKey, _ bytes: UInt64) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatGB(bytes))
                .monospacedDigit()
        }
        .font(.callout)
    }

    // MARK: - Top processes

    private var topProcesses: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Top ứng dụng dùng RAM")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Activity Monitor") {
                    monitor.openActivityMonitor()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if monitor.processes.isEmpty {
                Text("Đang tải…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(monitor.processes) { process in
                    HStack(spacing: 8) {
                        Button {
                            monitor.openProcess(process)
                        } label: {
                            Text(process.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .help("Mở \(process.name)")
                        Spacer(minLength: 4)
                        if process.cpuPercent > 0.5 {
                            Text(String(format: "%.0f%%", process.cpuPercent))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                        Text(formatGB(process.residentBytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                        Button {
                            monitor.forceQuit(process)
                        } label: {
                            Image(systemName: "power")
                        }
                        .buttonStyle(.borderless)
                        .help("Force Quit \(process.name)")
                    }
                    .font(.callout)
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 8) {
            Menu {
                Button {
                    Task { await monitor.purgeRAM() }
                } label: {
                    if monitor.isPurging {
                        Text("Đang giải phóng…")
                    } else {
                        Label("Giải phóng RAM", systemImage: "arrow.down.circle")
                    }
                }
                .disabled(monitor.isPurging)

                Divider()

                Button {
                    Task {
                        await cleaner.scan()
                        guard !cleaner.items.isEmpty else { return }
                        let list = cleaner.items
                            .map { "\($0.localizedTitle): \(formatGB($0.bytes))" }
                            .joined(separator: "\n")
                        AppAlert.show(
                            title: "Dọn ổ đĩa?",
                            message: list,
                            confirmTitle: "Dọn ngay",
                            destructive: true
                        ) {
                            Task { await cleaner.clean() }
                        }
                    }
                } label: {
                    switch cleaner.state {
                    case .scanning: Text("Đang quét…")
                    case .cleaning: Text("Đang dọn…")
                    default: Text("Dọn ổ đĩa")
                    }
                }
                .disabled(cleaner.state != .idle)

                Button {
                    Task {
                        await cleaner.scanAdmin()
                        guard cleaner.adminBytes > 0 else { return }
                        AppAlert.show(
                            title: "Dọn sâu (Admin)?",
                            message: String(format: NSLocalizedString("Xóa cache & log cấp hệ thống (khoảng %@). Cần mật khẩu admin.", comment: ""), formatGB(cleaner.adminBytes)),
                            confirmTitle: "Dọn ngay",
                            destructive: true
                        ) {
                            Task { await cleaner.cleanAdmin() }
                        }
                    }
                } label: {
                    if cleaner.isAdminCleaning {
                        Text("Đang dọn hệ thống…")
                    } else {
                        Text("Dọn hệ thống (Admin)")
                    }
                }
                .disabled(cleaner.isAdminCleaning || cleaner.state != .idle)
            } label: {
                Label("Dọn dẹp", systemImage: "internaldrive")
                    .frame(maxWidth: .infinity)
            }

            Menu {
                Toggle("Khởi động cùng macOS", isOn: Binding(
                    get: { monitor.loginItemEnabled },
                    set: { monitor.setLoginItem($0) }
                ))

                Divider()

                Picker("Ngôn ngữ", selection: $appLanguage) {
                    Text("Theo hệ thống").tag("system")
                    Text("Tiếng Việt").tag("vi")
                    Text("English").tag("en")
                }
                .onChange(of: appLanguage) { newValue in
                    applyLanguage(newValue)
                }

                Picker("Hiển thị Menu Bar", selection: $menuBarFormat) {
                    Text("Phần trăm (%)").tag("percent")
                    Text("Dung lượng (GB)").tag("gb")
                    Text("RAM % · CPU %").tag("ram_cpu")
                }

                Divider()

                Button {
                    updater.check()
                } label: {
                    updateMenuLabel
                }
                .disabled(updater.state == .checking || updater.state == .downloading)

                Divider()

                Button("Thoát ClearMMR") {
                    NSApp.terminate(nil)
                }

                Button("Gỡ cài đặt", role: .destructive) {
                    AppAlert.show(
                        title: "Gỡ cài đặt ClearMMR?",
                        message: NSLocalizedString("App sẽ chuyển vào Thùng rác, gỡ khỏi login items và thoát ngay.", comment: ""),
                        confirmTitle: "Gỡ cài đặt",
                        destructive: true,
                        onConfirm: { uninstall() }
                    )
                }
            } label: {
                Label("Tùy chọn", systemImage: "ellipsis.circle")
                    .frame(maxWidth: .infinity)
            }

            if let message = cleaner.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let freed = cleaner.lastFreed {
                Text("Đã giải phóng \(formatGB(freed))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.green)
            }
            if case .failed(let message) = updater.state {
                Text("Lỗi: \(message)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Text("Ngưỡng")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Vàng \(warnThreshold)%", value: $warnThreshold, in: 50...95)
                    .font(.caption)
                Stepper("Đỏ \(critThreshold)%", value: $critThreshold, in: 60...99)
                    .font(.caption)
            }
            .onChange(of: warnThreshold) { _ in
                if critThreshold <= warnThreshold { critThreshold = min(warnThreshold + 5, 99) }
            }
        }
        .font(.callout)
    }

    private var updateMenuLabel: Text {
        switch updater.state {
        case .checking: return Text("Đang kiểm tra…")
        case .downloading: return Text("Đang cập nhật…")
        case .available(let tag): return Text("Cập nhật lên \(tag)")
        default: return Text("Kiểm tra cập nhật")
        }
    }

    private func applyLanguage(_ code: String) {
        let defaults = UserDefaults.standard
        if code == "system" {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([code], forKey: "AppleLanguages")
        }
        AppAlert.show(
            title: "Ngôn ngữ",
            message: NSLocalizedString("Đã đổi ngôn ngữ. Khởi động lại app để áp dụng?", comment: ""),
            confirmTitle: "Khởi động lại",
            cancelTitle: "Để sau",
            onConfirm: { relaunch() }
        )
    }

    private func relaunch() {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", Bundle.main.bundleURL.path]
        try? open.run()
        NSApp.terminate(nil)
    }

    private func uninstall() {
        monitor.setLoginItem(false)
        let bundle = Bundle.main.bundleURL
        do {
            try FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
        } catch {
            try? FileManager.default.moveItem(
                at: bundle,
                to: FileManager.default.temporaryDirectory
                    .appendingPathComponent("ClearMMR.app")
            )
        }
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func formatGB(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / Double(1 << 30))
    }
}

@MainActor
enum AppAlert {
    static func show(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String = "Hủy",
        destructive: Bool = false,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString(title, comment: "")
        alert.informativeText = message
        alert.alertStyle = destructive ? .warning : .informational

        let confirm = alert.addButton(withTitle: NSLocalizedString(confirmTitle, comment: ""))
        confirm.hasDestructiveAction = destructive
        _ = alert.addButton(withTitle: NSLocalizedString(cancelTitle, comment: ""))

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        if alert.runModal() == .alertFirstButtonReturn {
            onConfirm()
        } else {
            onCancel?()
        }
    }
}

struct SparklineView: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(values.max() ?? 100, 1)
            let minVal = min(values.min() ?? 0, maxVal - 1)
            let span = max(maxVal - minVal, 1)
            Path { path in
                for (idx, val) in values.enumerated() {
                    let x = geo.size.width * CGFloat(idx) / CGFloat(max(values.count - 1, 1))
                    let y = geo.size.height * (1 - CGFloat((val - minVal) / span))
                    if idx == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}
