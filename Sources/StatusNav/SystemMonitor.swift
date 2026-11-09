import AppKit
import Combine
import CoreWLAN
import IOKit
import IOKit.ps
import Network
import StatusNavCore

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var battery = BatteryState()
    @Published private(set) var network = NetworkState()
    let bluetooth = BluetoothMonitor()
    let telemetry = TelemetryMonitor()
    @Published private(set) var bluetoothEnabled = true
    @Published private(set) var appActivityEnabled = true
    private var started = false
    private var panelVisible = false
    private var powerDetailsVisible = false
    private var menuPower = false
    private var menuRates = false
    let audio = AudioController()
    let inputAudio = AudioController(direction: .input)
    private let pathMonitor = NWPathMonitor()
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?
    private var pathKind: ConnectionKind = .offline
    private var pathInterface: String?
    private var pathIsExpensive = false
    private var pathIsConstrained = false
    private var observers: [NSObjectProtocol] = []

    func start() {
        started = true
        refresh()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let kind: ConnectionKind = path.status != .satisfied ? .offline
                : path.usesInterfaceType(.wifi) ? .wifi
                : path.usesInterfaceType(.wiredEthernet) ? .ethernet : .other
            let interface = path.availableInterfaces.first {
                switch kind {
                case .wifi: return $0.type == .wifi
                case .ethernet: return $0.type == .wiredEthernet
                case .other: return path.usesInterfaceType($0.type) && $0.type != .loopback
                case .offline: return false
                }
            }?.name
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            Task { @MainActor [weak self] in
                self?.pathInterface = interface
                self?.pathIsExpensive = expensive
                self?.pathIsConstrained = constrained
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
        ) { [weak self] _ in Task { @MainActor in self?.telemetry.reset(); self?.bluetooth.invalidate(); self?.refresh() } })
        audio.start()
        inputAudio.start()
        updateSamplingPolicy()
    }

    func stop(preserveReadings: Bool = false) {
        started = false
        bluetooth.stop()
        telemetry.stop(preserveReadings: preserveReadings)
        timer?.invalidate()
        timer = nil
        pathMonitor.cancel()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        audio.stop()
        inputAudio.stop()
    }

    func configure(settings: SettingsStore) {
        if bluetoothEnabled != settings.showBluetoothPanel { bluetoothEnabled = settings.showBluetoothPanel }
        if appActivityEnabled != settings.showApplicationActivity { appActivityEnabled = settings.showApplicationActivity }
        menuPower = settings.showBatteryPowerInMenuBar
        menuRates = settings.showNetworkRatesInMenuBar
        updateSamplingPolicy()
    }

    func setPanelVisible(_ shown: Bool) {
        guard panelVisible != shown else { return }
        panelVisible = shown
        updateSamplingPolicy()
    }
    func setPowerDetailsVisible(_ shown: Bool) {
        guard powerDetailsVisible != shown else { return }
        powerDetailsVisible = shown
        updateSamplingPolicy()
    }
    private func updateSamplingPolicy() {
        bluetooth.setActive(started && panelVisible && bluetoothEnabled)
        telemetry.configure(power: started && (panelVisible || menuPower),
                            rates: started && (panelVisible || menuRates),
                            applications: started && panelVisible && powerDetailsVisible && appActivityEnabled)
    }

    func refresh() {
        refreshBattery()
        refreshNetwork()
        audio.refresh()
        inputAudio.refresh()
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
                minutesToFull: info[kIOPSTimeToFullChargeKey] as? Int,
                fullyCharged: info[kIOPSIsChargedKey] as? Bool ?? false
            )
            battery.details = BatteryDetailsReader.read(source: info, externalPower: battery.externalPower)
            telemetry.update(interface: network.interfaceName,
                             context: BatteryPowerContext(external: battery.externalPower, charging: battery.charging))
            return
        }
        battery = BatteryState()
    }

    private func refreshNetwork() {
        let client = CWWiFiClient.shared()
        let interface: CWInterface?
        if pathKind == .wifi, let name = pathInterface { interface = client.interface(withName: name) }
        else { interface = client.interface() }
        var next = NetworkState()
        next.kind = pathKind
        next.interfaceName = pathKind == .offline ? nil : pathInterface
        next.isExpensive = pathIsExpensive
        next.isConstrained = pathIsConstrained
        if let name = next.interfaceName {
            let addresses = NetworkAddresses.read(interface: name)
            next.ipv4Address = addresses.ipv4
            next.ipv6Address = addresses.ipv6
        }
        next.wifiEnabled = interface?.powerOn() ?? false
        // macOS may withhold SSID without location access; connection state comes from NWPath.
        if pathKind == .wifi {
            next.name = interface?.ssid()
            let rssi = interface?.rssiValue() ?? 0
            next.rssi = (-127..<0).contains(rssi) ? rssi : nil
            if let interface {
                let rate = interface.transmitRate()
                next.transmitRate = rate.isFinite && rate > 0 ? rate : nil
                let noise = interface.noiseMeasurement()
                next.noise = (-127..<0).contains(noise) ? noise : nil
                if let channel = interface.wlanChannel() {
                    next.channel = channel.channelNumber > 0 ? channel.channelNumber : nil
                    switch channel.channelBand {
                    case .band2GHz: next.band = "2.4 GHz"
                    case .band5GHz: next.band = "5 GHz"
                    case .band6GHz: next.band = "6 GHz"
                    default: break
                    }
                }
                switch interface.activePHYMode().rawValue {
                case 1: next.standard = "802.11a"
                case 2: next.standard = "802.11b"
                case 3: next.standard = "802.11g"
                case 4: next.standard = "Wi-Fi 4 · 802.11n"
                case 5: next.standard = "Wi-Fi 5 · 802.11ac"
                case 6: next.standard = "Wi-Fi 6 · 802.11ax"
                case 7: next.standard = "Wi-Fi 7 · 802.11be"
                default: break
                }
                switch interface.security() {
                case .none: next.security = "开放网络"
                case .WEP, .dynamicWEP: next.security = "WEP"
                case .wpaPersonal: next.security = "WPA 个人级"
                case .wpaPersonalMixed: next.security = "WPA / WPA2 个人级"
                case .wpa2Personal: next.security = "WPA2 个人级"
                case .wpa3Personal: next.security = "WPA3 个人级"
                case .wpa3Transition: next.security = "WPA2 / WPA3 个人级"
                case .wpaEnterprise: next.security = "WPA 企业级"
                case .wpaEnterpriseMixed: next.security = "WPA / WPA2 企业级"
                case .wpa2Enterprise: next.security = "WPA2 企业级"
                case .wpa3Enterprise: next.security = "WPA3 企业级"
                case .OWE, .oweTransition: next.security = "增强型开放网络"
                default: break
                }
            }
        }
        network = next
        telemetry.update(interface: next.interfaceName,
                         context: BatteryPowerContext(external: battery.externalPower, charging: battery.charging))
    }
}
