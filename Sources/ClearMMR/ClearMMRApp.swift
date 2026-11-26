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
        case 90...: return .red
        case 80..<90: return .yellow
        default: return .primary
        }
    }
}


