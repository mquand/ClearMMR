import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var monitor: RAMMonitor
    @EnvironmentObject private var updater: AppUpdater
    @EnvironmentObject private var cleaner: DiskCleaner
    @State private var showUpdateAlert = false
    @State private var showCleanAlert = false
    @State private var showAdminAlert = false
    @State private var showUninstallAlert = false

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
            monitor.refreshLoginItemStatus()
            updater.checkIfNeeded()
        }
        .onChange(of: updater.state) { newState in
            if case .available = newState { showUpdateAlert = true }
        }
        .onChange(of: cleaner.lastFreed) { freed in
            if freed != nil { monitor.refresh() }
        }
        .alert("Có bản cập nhật mới", isPresented: $showUpdateAlert) {
            Button("Cập nhật") { updater.install() }
            Button("Để sau", role: .cancel) { updater.dismiss() }
        } message: {
            Text("Phiên bản \(updater.latestTag) đã sẵn sàng. App sẽ tự tải, cài đặt và khởi động lại.")
        }
        .alert("Dọn ổ đĩa?", isPresented: $showCleanAlert) {
            Button("Dọn ngay", role: .destructive) {
                Task { await cleaner.clean() }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text(cleaner.items.map { "\($0.localizedTitle): \(formatGB($0.bytes))" }
                .joined(separator: "\n"))
        }
        .alert("Dọn sâu (Admin)?", isPresented: $showAdminAlert) {
            Button("Dọn ngay", role: .destructive) {
                Task { await cleaner.cleanAdmin() }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Xóa cache & log cấp hệ thống (khoảng \(formatGB(cleaner.adminBytes))). Cần mật khẩu admin.")
        }
        .alert("Gỡ cài đặt ClearMMR?", isPresented: $showUninstallAlert) {
            Button("Gỡ cài đặt", role: .destructive) { uninstall() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("App sẽ chuyển vào Thùng rác, gỡ khỏi login items và thoát ngay.")
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
        }
    }

    private var headerColor: Color {
        switch monitor.percent {
        case 90...: return .red
        case 80..<90: return .yellow
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
        }
    }

    private func statBox(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Text("Top ứng dụng dùng RAM")
                .font(.callout)
                .foregroundStyle(.secondary)

            if monitor.processes.isEmpty {
                Text("Đang tải…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(monitor.processes) { process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
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
        VStack(spacing: 10) {
            Button {
                Task { await monitor.purgeRAM() }
            } label: {
                if monitor.isPurging {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Đang giải phóng…")
                    }
                } else {
                    Label("Giải phóng RAM", systemImage: "arrow.down.circle")
                }
            }
            .disabled(monitor.isPurging)
            .frame(maxWidth: .infinity)

            Button {
                Task {
                    await cleaner.scan()
                    if !cleaner.items.isEmpty { showCleanAlert = true }
                }
            } label: {
                switch cleaner.state {
                case .scanning: Label("Đang quét…", systemImage: "internaldrive")
                case .cleaning: Label("Đang dọn…", systemImage: "internaldrive")
                default: Label("Dọn ổ đĩa", systemImage: "internaldrive")
                }
            }
            .disabled(cleaner.state != .idle)
            .frame(maxWidth: .infinity)

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

            Button {
                Task {
                    await cleaner.scanAdmin()
                    if cleaner.adminBytes > 0 { showAdminAlert = true }
                }
            } label: {
                if cleaner.isAdminCleaning {
                    Label("Đang dọn hệ thống…", systemImage: "internaldrive")
                } else {
                    Label("Dọn hệ thống (Admin)", systemImage: "internaldrive.badge.plus")
                }
            }
            .disabled(cleaner.isAdminCleaning || cleaner.state != .idle)
            .font(.caption)
            .frame(maxWidth: .infinity)

            Toggle("Khởi động cùng macOS", isOn: Binding(
                get: { monitor.loginItemEnabled },
                set: { monitor.setLoginItem($0) }
            ))

            HStack {
                Button {
                    updater.check()
                } label: {
                    Label(updateButtonTitle, systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(updater.state == .checking || updater.state == .downloading)

                if case .failed(let message) = updater.state {
                    Text("Lỗi: \(message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Button("Thoát ClearMMR") {
                NSApp.terminate(nil)
            }
            .frame(maxWidth: .infinity)

            Button("Gỡ cài đặt", role: .destructive) {
                showUninstallAlert = true
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
        }
        .font(.callout)
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

    private var updateButtonTitle: LocalizedStringKey {
        switch updater.state {
        case .checking: return "Đang kiểm tra…"
        case .downloading: return "Đang cập nhật…"
        case .available(let tag): return "Cập nhật lên \(tag)"
        default: return "Kiểm tra cập nhật"
        }
    }

    // MARK: - Helpers

    private func formatGB(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / Double(1 << 30))
    }
}
