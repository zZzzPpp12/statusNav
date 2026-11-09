import Combine
import Foundation
import StatusNavCore

@MainActor
final class BluetoothMonitor: ObservableObject {
    @Published private(set) var snapshot = BluetoothSnapshot()
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var active = false
    private var running = false
    private var generation = 0
    private var timer: Timer?
    private var lastAttempt: Date?

    func setActive(_ enabled: Bool) {
        guard active != enabled else { return }
        active = enabled; generation += 1
        timer?.invalidate(); timer = nil
        if enabled {
            refresh(force: false)
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh(force: false) }
            }
        } else { loading = false }
    }

    func refresh(force: Bool = true) {
        guard active, !running else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 15 { return }
        lastAttempt = Date(); loading = true; running = true; error = nil
        let epoch = generation
        Task.detached(priority: .utility) { [weak self] in
            let data = LocalReportProcess.read("/usr/sbin/system_profiler", arguments: ["-json", "SPBluetoothDataType"], timeout: 8)
            var result = data.flatMap { BluetoothSnapshot.parse($0) }
            if result != nil { result?.fillMissingBatteryLevels(BluetoothHIDBatteryReader.read()) }
            await self?.complete(result, epoch: epoch)
        }
    }

    private func complete(_ value: BluetoothSnapshot?, epoch: Int) {
        running = false
        guard active, epoch == generation else {
            if active { refresh(force: true) }
            return
        }
        loading = false
        if let value { snapshot = value; error = nil }
        else {
            snapshot = BluetoothSnapshot()
            error = "蓝牙信息暂时无法读取，请重试或检查系统授权。"
        }
    }

    func invalidate() {
        generation += 1; snapshot = BluetoothSnapshot(); lastAttempt = nil; error = nil
        if active { refresh(force: true) }
    }
    func stop() { setActive(false) }
}
