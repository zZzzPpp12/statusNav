import AppKit
import Combine
import CoreWLAN
import IOKit.ps
import Network
import StatusNavCore

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var battery = BatteryState()
    @Published private(set) var network = NetworkState()
    let audio = AudioController()
    private let pathMonitor = NWPathMonitor()
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?
    private var pathKind: ConnectionKind = .offline
    private var observers: [NSObjectProtocol] = []

    func start() {
        refresh()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let kind: ConnectionKind = path.status != .satisfied ? .offline
                : path.usesInterfaceType(.wifi) ? .wifi
                : path.usesInterfaceType(.wiredEthernet) ? .ethernet : .other
            Task { @MainActor [weak self] in
                self?.pathKind = kind
                self?.refreshNetwork()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "StatusNav.network"))
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.refreshBattery() }
        }, context)?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        audio.start()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pathMonitor.cancel()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        audio.stop()
    }

    func refresh() {
        refreshBattery()
        refreshNetwork()
        audio.refresh()
    }

    private func refreshBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            battery = BatteryState()
            return
        }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let percentage: Int?
            if let current = info[kIOPSCurrentCapacityKey] as? Int,
               let maximum = info[kIOPSMaxCapacityKey] as? Int {
                percentage = BatteryState.percentage(current: current, maximum: maximum)
            } else { percentage = nil }
            battery = BatteryState(
                percentage: percentage,
                charging: info[kIOPSIsChargingKey] as? Bool ?? false,
                externalPower: info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesToFull: info[kIOPSTimeToFullChargeKey] as? Int
            )
            return
        }
        battery = BatteryState()
    }

    private func refreshNetwork() {
        let interface = CWWiFiClient.shared().interface()
        var next = NetworkState()
        next.kind = pathKind
        next.wifiEnabled = interface?.powerOn() ?? false
        // macOS may withhold SSID without location access; connection state comes from NWPath.
        if pathKind == .wifi {
            next.name = interface?.ssid()
            let rssi = interface?.rssiValue() ?? 0
            next.rssi = rssi < 0 ? rssi : nil
        }
        network = next
    }
}
