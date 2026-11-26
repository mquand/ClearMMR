import SwiftUI

@main
struct ClearMMRApp: App {
    @StateObject private var monitor = RAMMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
        } label: {
            RAMMenuLabel(percent: monitor.percent)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RAMMenuLabel: View {
    let percent: Double

    var body: some View {
        Text("RAM \(Int(percent.rounded()))%")
            .monospacedDigit()
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
