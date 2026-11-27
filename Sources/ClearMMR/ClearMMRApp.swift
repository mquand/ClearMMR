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
        } label: {
            RAMMenuLabel(percent: monitor.percent)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RAMMenuLabel: View {
    let percent: Double
    @AppStorage("warnThreshold") private var warnThreshold = 80
    @AppStorage("critThreshold") private var critThreshold = 90

    var body: some View {
        Label {
            Text("\(Int(percent.rounded()))%")
                .monospacedDigit()
        } icon: {
            Image(systemName: "memorychip")
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(color)
    }

    private var color: Color {
        switch percent {
        case Double(critThreshold)...: return .red
        case Double(warnThreshold)..<Double(critThreshold): return .yellow
        default: return .primary
        }
    }
}


