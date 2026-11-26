import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var monitor: RAMMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
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

    // MARK: - Breakdown

    private var memoryBreakdown: some View {
        VStack(spacing: 6) {
            statRow("Active", monitor.activeBytes)
            statRow("Wired", monitor.wiredBytes)
            statRow("Compressed", monitor.compressedBytes)
        }
    }

    private func statRow(_ title: String, _ bytes: UInt64) -> some View {
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
                        Text(formatGB(process.residentBytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
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
