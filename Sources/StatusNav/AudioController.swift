import Combine
import CoreAudio
import Foundation
import StatusNavCore

enum AudioDirection {
    case output, input

    var scope: AudioObjectPropertyScope {
        self == .output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput
    }
    var defaultDeviceProperty: AudioObjectPropertySelector {
        self == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
    }
}

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32
    let sampleRate: Double?

    var connectionName: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: "内置"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "蓝牙"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "显示器"
        case kAudioDeviceTransportTypeAirPlay: "AirPlay"
        case kAudioDeviceTransportTypeVirtual: "虚拟设备"
        default: "音频设备"
        }
    }

    func symbol(direction: AudioDirection) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "display"
        case kAudioDeviceTransportTypeAirPlay: "airplay.audio"
        case kAudioDeviceTransportTypeVirtual: "waveform"
        default: direction == .input ? "mic.fill" : "speaker.wave.2.fill"
        }
    }

    var subtitle: String {
        guard let sampleRate else { return connectionName }
        let kilohertz = sampleRate / 1_000
        let rate = kilohertz.formatted(.number.precision(.fractionLength(0...1)))
        return "\(connectionName) · \(rate) kHz"
    }
}

@MainActor
final class AudioController: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var deviceID = AudioDeviceID(0)
    @Published private(set) var volume: Double = 0
    @Published private(set) var muted = false
    @Published private(set) var hasVolumeReading = false
    @Published private(set) var canSetVolume = false
    @Published private(set) var canMute = false
    @Published var error: String?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    let direction: AudioDirection
    private let callbackQueue = DispatchQueue(label: "StatusNav.audio")

    init(direction: AudioDirection = .output) { self.direction = direction }

    var deviceName: String { devices.first { $0.id == deviceID }?.name ?? "无可用设备" }

    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    func start() { refresh(); installListeners() }
    func stop() {
        for (object, var property, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(object, &property, callbackQueue, block)
        }
        listeners.removeAll()
    }

    private func listen(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress) {
        var property = property
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        if AudioObjectAddPropertyListenerBlock(object, &property, callbackQueue, block) == noErr {
            listeners.append((object, property, block))
        }
    }

    private func installListeners() {
        stop()
        listen(AudioObjectID(kAudioObjectSystemObject), address(direction.defaultDeviceProperty))
        listen(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDevices))
        guard deviceID != 0 else { return }
        listen(deviceID, address(kAudioDevicePropertyNominalSampleRate))
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element: UInt32 in [0, 1, 2] {
                listen(deviceID, address(selector, scope: direction.scope, element: element))
            }
        }
    }

    private func read<T>(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, into value: inout T) -> Bool {
        var property = property
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0) == noErr
        }
    }

    private func writable(_ property: AudioObjectPropertyAddress) -> Bool {
        var property = property
        var result = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(deviceID, &property, &result) == noErr && result.boolValue
    }

    private func volumeProperties() -> [AudioObjectPropertyAddress] {
        let main = address(kAudioDevicePropertyVolumeScalar, scope: direction.scope)
        if writable(main) { return [main] }
        return [UInt32(1), 2].map {
            address(kAudioDevicePropertyVolumeScalar, scope: direction.scope, element: $0)
        }.filter { writable($0) }
    }

    func refresh() {
        let previous = deviceID
        let system = AudioObjectID(kAudioObjectSystemObject)
        var current = AudioDeviceID(0)
        _ = read(system, address(direction.defaultDeviceProperty), into: &current)
        deviceID = current
        var listProperty = address(kAudioHardwarePropertyDevices)
        var bytes: UInt32 = 0
        var outputs: [AudioDevice] = []
        if AudioObjectGetPropertyDataSize(system, &listProperty, 0, nil, &bytes) == noErr, bytes > 0 {
            var ids = [AudioDeviceID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioDeviceID>.size)
            let result = ids.withUnsafeMutableBytes {
                AudioObjectGetPropertyData(system, &listProperty, 0, nil, &bytes, $0.baseAddress!)
            }
            if result == noErr {
                for id in ids {
                    var streams = address(kAudioDevicePropertyStreams, scope: direction.scope)
                    var streamBytes: UInt32 = 0
                    guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamBytes) == noErr,
                          streamBytes > 0 else { continue }
                    var name: Unmanaged<CFString>?
                    if read(id, address(kAudioObjectPropertyName), into: &name), let name {
                        // CoreAudio returns an owned CFString for this property.
                        let deviceName = name.takeRetainedValue() as String
                        var transport: UInt32 = 0
                        _ = read(id, address(kAudioDevicePropertyTransportType), into: &transport)
                        var rate: Float64 = 0
                        _ = read(id, address(kAudioDevicePropertyNominalSampleRate), into: &rate)
                        outputs.append(AudioDevice(id: id, name: deviceName, transport: transport,
                            sampleRate: rate.isFinite && rate > 0 ? rate : nil))
                    }
                }
            }
        }
        devices = outputs
        let properties = volumeProperties()
        canSetVolume = !properties.isEmpty
        var readings: [Double] = []
        // Read master volume even for read-only devices, then fall back to channels.
        for element: UInt32 in [0, 1, 2] {
            var scalar: Float32 = 0
            if read(deviceID, address(kAudioDevicePropertyVolumeScalar, scope: direction.scope, element: element), into: &scalar) {
                if scalar.isFinite, (0...1).contains(scalar) {
                    readings.append(Double(scalar))
                    if element == 0 { break }
                }
            }
        }
        hasVolumeReading = !readings.isEmpty
        volume = VolumeScale.normalized(readings.isEmpty ? 0 : readings.reduce(0, +) / Double(readings.count))
        let muteProperty = address(kAudioDevicePropertyMute, scope: direction.scope)
        var mute: UInt32 = 0
        muted = read(deviceID, muteProperty, into: &mute) && mute != 0
        canMute = writable(muteProperty)
        if current != previous { installListeners() }
    }

    func setVolume(_ value: Double) {
        let properties = volumeProperties()
        guard !properties.isEmpty else { return }
        var scalar = Float32(VolumeScale.normalized(value))
        var failed = false
        for var property in properties {
            if AudioObjectSetPropertyData(deviceID, &property, 0, nil, UInt32(MemoryLayout.size(ofValue: scalar)), &scalar) != noErr { failed = true }
        }
        if failed { error = "无法调整该设备音量，请使用设备或系统控制。" }
        refresh()
    }

    func toggleMute() {
        guard canMute else { return }
        var value: UInt32 = muted ? 0 : 1
        var property = address(kAudioDevicePropertyMute, scope: direction.scope)
        if AudioObjectSetPropertyData(deviceID, &property, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value) != noErr {
            error = "静音操作失败。"
        }
        refresh()
    }

    func selectDevice(_ id: AudioDeviceID) {
        guard devices.contains(where: { $0.id == id }) else { return }
        var id = id
        var property = address(direction.defaultDeviceProperty)
        if AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil,
                                      UInt32(MemoryLayout.size(ofValue: id)), &id) != noErr {
            error = direction == .output ? "无法切换输出设备。" : "无法切换输入设备。"
        }
        refresh()
    }
}
