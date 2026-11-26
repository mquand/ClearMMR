import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var monitor: RAMMonitor

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
        .onAppear { monitor.refreshLoginItemStatus() }
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

            Toggle("Khởi động cùng macOS", isOn: Binding(
                get: { monitor.loginItemEnabled },
                set: { monitor.setLoginItem($0) }
            ))

            Button("Thoát ClearMMR") {
                NSApp.terminate(nil)
            }
            .frame(maxWidth: .infinity)
        }
        .font(.callout)
    }

    // MARK: - Helpers

    private func formatGB(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / Double(1 << 30))
    }
}
