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
        HStack(spacing: 4) {
            RAMGlyph()
                .frame(width: 13, height: 13)
            Text("RAM \(Int(percent.rounded()))%")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
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

// Icon RAM stick vẽ tay: thân chip + chân pin 2 mép, dùng `.foreground` để
// đổi màu theo foregroundStyle của label (vàng/đỏ khi quá ngưỡng).
struct RAMGlyph: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let pinLen: CGFloat = 1.6
            let bodyRect = CGRect(x: w * 0.14, y: h * 0.24, width: w * 0.72, height: h * 0.52)

            // chân pin trái/phải (3 chân mỗi bên)
            for i in 0..<3 {
                let y = bodyRect.minY + bodyRect.height * (0.2 + 0.3 * CGFloat(i))
                var left = Path()
                left.move(to: CGPoint(x: 0, y: y))
                left.addLine(to: CGPoint(x: bodyRect.minX - pinLen, y: y))
                var right = Path()
                right.move(to: CGPoint(x: bodyRect.maxX + pinLen, y: y))
                right.addLine(to: CGPoint(x: w, y: y))
                context.stroke(left, with: .foreground, lineWidth: 0.9)
                context.stroke(right, with: .foreground, lineWidth: 0.9)
            }

            // thân chip bo góc
            context.stroke(
                Path(roundedRect: bodyRect, cornerRadius: 1.2),
                with: .foreground,
                lineWidth: 0.9
            )
        }
    }
}
