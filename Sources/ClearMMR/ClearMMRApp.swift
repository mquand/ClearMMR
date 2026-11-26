import SwiftUI

@main
struct ClearMMRApp: App {
    @StateObject private var monitor = RAMMonitor()
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(updater)
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
            Text("RAM \(Int(percent.rounded()))%")
                .monospacedDigit()
        } icon: {
            Image(systemName: "memorychip")
        }
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


