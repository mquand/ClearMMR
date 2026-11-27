import SwiftUI

@main
struct ClearMMRApp: App {
    @StateObject private var monitor = RAMMonitor()
    @StateObject private var updater = AppUpdater()
    @StateObject private var cleaner = DiskCleaner()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(updater)
                .environmentObject(cleaner)
                .onAppear { registerHotkeyIfNeeded() }
        } label: {
            RAMMenuLabel(percent: monitor.percent, usedBytes: monitor.usedBytes, cpuPercent: monitor.cpuPercent)
        }
        .menuBarExtraStyle(.window)
    }

    private func registerHotkeyIfNeeded() {
        struct Holder { static var installed = false }
        guard !Holder.installed else { return }
        Holder.installed = true
        let m = monitor
        let handler: (NSEvent) -> Void = { event in
            // ⌥⌘R (keyCode 15) -> Purge RAM nhanh
            if event.keyCode == 15 && event.modifierFlags.intersection([.option, .command, .shift, .control]) == [.option, .command] {
                Task { @MainActor in
                    m.purge()
                }
            }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
    }
}

struct RAMMenuLabel: View {
    let percent: Double
    let usedBytes: UInt64
    let cpuPercent: Double
    @AppStorage("warnThreshold") private var warnThreshold = 80
    @AppStorage("critThreshold") private var critThreshold = 90
    @AppStorage("menuBarFormat") private var menuBarFormat = "percent"

    var body: some View {
        Label {
            Text(labelText)
                .monospacedDigit()
        } icon: {
            Image(systemName: "memorychip")
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(color)
    }

    private var labelText: String {
        switch menuBarFormat {
        case "gb":
            let gb = Double(usedBytes) / 1_073_741_824
            return String(format: "%.1fG", gb)
        case "ram_cpu":
            return "\(Int(percent.rounded()))% · \(Int(cpuPercent.rounded()))%"
        default:
            return "\(Int(percent.rounded()))%"
        }
    }

    private var color: Color {
        switch percent {
        case Double(critThreshold)...: return .red
        case Double(warnThreshold)..<Double(critThreshold): return .yellow
        default: return .primary
        }
    }
}


