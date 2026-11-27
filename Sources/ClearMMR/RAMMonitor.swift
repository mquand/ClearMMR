import Foundation
import AppKit
import ServiceManagement
import UserNotifications
import Darwin

struct ProcessMemory: Identifiable, Hashable {
    let pid: pid_t
    let name: String
    let residentBytes: UInt64
    var cpuPercent: Double = 0

    var id: pid_t { pid }
}

@MainActor
final class RAMMonitor: ObservableObject {
    @Published private(set) var totalBytes: UInt64 = 0
    @Published private(set) var usedBytes: UInt64 = 0
    @Published private(set) var activeBytes: UInt64 = 0
    @Published private(set) var wiredBytes: UInt64 = 0
    @Published private(set) var compressedBytes: UInt64 = 0
    @Published private(set) var cpuPercent: Double = 0
    @Published private(set) var swapUsedBytes: UInt64 = 0
    @Published private(set) var swapTotalBytes: UInt64 = 0
    @Published private(set) var diskFreeBytes: UInt64 = 0
    @Published private(set) var diskTotalBytes: UInt64 = 0
    @Published private(set) var processes: [ProcessMemory] = []
    @Published private(set) var isPurging = false
    @Published private(set) var loginItemEnabled = false
    @Published private(set) var pressureLevel: Int32 = 1

    private let pageSize: UInt64
    private var monitorTask: Task<Void, Never>?
    private var lastCPUInfo: host_cpu_load_info?
    private var procLastSample: [pid_t: (cpuTime: UInt64, uptime: TimeInterval)] = [:]

    var percent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }

    init() {
        pageSize = Self.readPageSize()
        totalBytes = Self.readTotalMemory()
        refreshLoginItemStatus()
        start()
    }

    deinit {
        monitorTask?.cancel()
    }

    // MARK: - Monitoring loop

    private func start() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    func refresh() {
        guard let stats = readHostStats() else { return }
        usedBytes = stats.used
        activeBytes = stats.active
        wiredBytes = stats.wired
        compressedBytes = stats.compressed
        cpuPercent = readCPUUsage() ?? cpuPercent
        if let swap = readSwapUsage() {
            swapUsedBytes = swap.used
            swapTotalBytes = swap.total
        }
        if let disk = readDiskSpace() {
            diskFreeBytes = disk.free
            diskTotalBytes = disk.total
        }
        pressureLevel = readMemoryPressure() ?? pressureLevel
        processes = topProcesses(limit: 5)
    }

    // MARK: - host_statistics64

    private func readHostStats() -> (used: UInt64, active: UInt64, wired: UInt64, compressed: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        return (active + wired + compressed, active, wired, compressed)
    }

    // MARK: - Process list (libproc)

    private func topProcesses(limit: Int) -> [ProcessMemory] {
        var size = proc_listallpids(nil, 0)
        guard size > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.stride + 64)
        size = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard size > 0 else { return [] }

        var result: [ProcessMemory] = []
        result.reserveCapacity(limit * 4)
        let ownPid = getpid()
        let nowUptime = ProcessInfo.processInfo.systemUptime
        var seenPids = Set<pid_t>()

        for pid in pids.prefix(Int(size)) where pid > 1 && pid != ownPid {
            var taskInfo = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize) > 0 else { continue }

            var bsdInfo = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
            _ = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize)

            let name = Self.processName(from: &bsdInfo) ?? "pid \(pid)"
            let cpuTime = taskInfo.pti_total_user &+ taskInfo.pti_total_system
            let cpuPercent = processCPUPercent(pid: pid, cpuTime: cpuTime, uptime: nowUptime)
            seenPids.insert(pid)
            result.append(ProcessMemory(
                pid: pid,
                name: name,
                residentBytes: taskInfo.pti_resident_size,
                cpuPercent: cpuPercent
            ))
        }

        procLastSample = procLastSample.filter { seenPids.contains($0.key) }
        return Array(result.sorted { $0.residentBytes > $1.residentBytes }.prefix(limit))
    }

    // pti_total_user/pti_total_system của proc_taskinfo tính bằng nanosecond
    private func processCPUPercent(pid: pid_t, cpuTime: UInt64, uptime: TimeInterval) -> Double {
        defer { procLastSample[pid] = (cpuTime, uptime) }
        guard let prev = procLastSample[pid], uptime > prev.uptime else { return 0 }
        let deltaProc = Double(cpuTime &- prev.cpuTime) / 1_000_000_000
        let deltaWall = uptime - prev.uptime
        guard deltaWall > 0 else { return 0 }
        return min(deltaProc / deltaWall * 100, 100 * Double(ProcessInfo.processInfo.activeProcessorCount))
    }

    private static func processName(from info: inout proc_bsdinfo) -> String? {
        var nameTuple = info.pbi_name
        let bytes = withUnsafeBytes(of: &nameTuple) { Data($0) }
        let name = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    // MARK: - Actions

    func forceQuit(_ process: ProcessMemory) {
        if let app = NSRunningApplication(processIdentifier: process.pid),
           app.forceTerminate() {
            return
        }
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/bin/kill")
        kill.arguments = ["-9", "\(process.pid)"]
        try? kill.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    func purgeRAM() async {
        isPurging = true
        defer { isPurging = false }

        await requestNotificationAuthorization()

        var error: NSDictionary?
        NSAppleScript(source: #"do shell script "/usr/sbin/purge" with administrator privileges"#)?
            .executeAndReturnError(&error)

        // purge cần vài giây để giải phóng file cache
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        refresh()

        if let error {
            let cancelled = (error["NSAppleScriptErrorNumber"] as? Int) == 128
            if cancelled {
                notify(title: "ClearMMR", body: NSLocalizedString("Đã hủy giải phóng RAM.", comment: ""))
            } else {
                let detail = error["NSAppleScriptErrorMessage"] as? String ?? "unknown"
                notify(title: "ClearMMR", body: String(
                    format: NSLocalizedString("Giải phóng RAM thất bại: %@", comment: ""),
                    detail
                ))
            }
        } else {
            notify(title: "ClearMMR", body: String(
                format: NSLocalizedString("Đã giải phóng RAM. Hiện còn %lld%%.", comment: ""),
                Int(percent.rounded())
            ))
        }
    }

    func setLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // App chưa nằm trong .app bundle (vd: `swift run`) thì bỏ qua
        }
        refreshLoginItemStatus()
    }

    func refreshLoginItemStatus() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            loginItemEnabled = false
            return
        }
        loginItemEnabled = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Notifications

    private func requestNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - CPU / Swap / Disk

    private func readCPUUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        defer { lastCPUInfo = info }
        guard let prev = lastCPUInfo else { return nil }

        let user = Int64(info.cpu_ticks.0) &- Int64(prev.cpu_ticks.0)
        let system = Int64(info.cpu_ticks.1) &- Int64(prev.cpu_ticks.1)
        let idle = Int64(info.cpu_ticks.2) &- Int64(prev.cpu_ticks.2)
        let nice = Int64(info.cpu_ticks.3) &- Int64(prev.cpu_ticks.3)
        let total = user &+ system &+ idle &+ nice
        guard total > 0 else { return nil }
        return Double(user &+ system &+ nice) / Double(total) * 100
    }

    // Layout giống struct xsw_usage trong <sys/sysctl.h> (đã verify: total/avail/used tính bằng bytes)
    private struct SwapUsage {
        var xsu_total: UInt64 = 0
        var xsu_avail: UInt64 = 0
        var xsu_used: UInt64 = 0
        var xsu_pagesize: UInt32 = 0
        var xsu_encrypted: Int32 = 0
    }

    private func readSwapUsage() -> (used: UInt64, total: UInt64)? {
        var usage = SwapUsage()
        var size = MemoryLayout<SwapUsage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0, usage.xsu_total > 0 else { return nil }
        return (usage.xsu_used, usage.xsu_total)
    }

    // kern.memorystatus_vm_pressure_level: 1 = normal, 2 = warn, 4 = critical
    private func readMemoryPressure() -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.stride
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else {
            return nil
        }
        return value
    }

    private func readDiskSpace() -> (free: UInt64, total: UInt64)? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") else {
            return nil
        }
        guard let free = attrs[.systemFreeSize] as? NSNumber,
              let total = attrs[.systemSize] as? NSNumber else { return nil }
        return (free.uint64Value, total.uint64Value)
    }

    // MARK: - Sysctl helpers

    private static func readPageSize() -> UInt64 {
        var size = 0
        var value: UInt64 = 0
        size = MemoryLayout<UInt64>.stride
        sysctlbyname("hw.pagesize", &value, &size, nil, 0)
        return value > 0 ? value : 4096
    }

    private static func readTotalMemory() -> UInt64 {
        var size = 0
        var value: UInt64 = 0
        size = MemoryLayout<UInt64>.stride
        sysctlbyname("hw.memsize", &value, &size, nil, 0)
        return value
    }
}
