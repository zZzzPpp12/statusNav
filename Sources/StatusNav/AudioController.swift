import Combine
import CoreAudio
import Foundation
import StatusNavCore

struct OutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

@MainActor
final class AudioController: ObservableObject {
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var deviceID = AudioDeviceID(0)
    @Published private(set) var volume: Double = 0
    @Published private(set) var muted = false
    @Published private(set) var canSetVolume = false
    @Published private(set) var canMute = false
    @Published var error: String?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private let callbackQueue = DispatchQueue(label: "StatusNav.audio")

    var deviceName: String { devices.first { $0.id == deviceID }?.name ?? "无可用输出设备" }

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
        listen(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultOutputDevice))
        listen(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDevices))
        guard deviceID != 0 else { return }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element: UInt32 in [0, 1, 2] {
                listen(deviceID, address(selector, scope: kAudioDevicePropertyScopeOutput, element: element))
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
        let main = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
        if writable(main) { return [main] }
        return [UInt32(1), 2].map {
            address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: $0)
        }.filter { writable($0) }
    }

    func refresh() {
        let previous = deviceID
        let system = AudioObjectID(kAudioObjectSystemObject)
        var current = AudioDeviceID(0)
        _ = read(system, address(kAudioHardwarePropertyDefaultOutputDevice), into: &current)
        deviceID = current
        var listProperty = address(kAudioHardwarePropertyDevices)
        var bytes: UInt32 = 0
        var outputs: [OutputDevice] = []
        if AudioObjectGetPropertyDataSize(system, &listProperty, 0, nil, &bytes) == noErr, bytes > 0 {
            var ids = [AudioDeviceID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioDeviceID>.size)
            let result = ids.withUnsafeMutableBytes {
                AudioObjectGetPropertyData(system, &listProperty, 0, nil, &bytes, $0.baseAddress!)
            }
            if result == noErr {
                for id in ids {
                    var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
                    var streamBytes: UInt32 = 0
                    guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamBytes) == noErr,
                          streamBytes > 0 else { continue }
                    var name: Unmanaged<CFString>?
                    if read(id, address(kAudioObjectPropertyName), into: &name), let name {
                        // CoreAudio returns an owned CFString for this property.
                        outputs.append(OutputDevice(id: id, name: name.takeRetainedValue() as String))
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
            if read(deviceID, address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element), into: &scalar) {
                readings.append(Double(scalar))
                if element == 0 { break }
            }
        }
        volume = VolumeScale.normalized(readings.isEmpty ? 0 : readings.reduce(0, +) / Double(readings.count))
        let muteProperty = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
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
        var property = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        if AudioObjectSetPropertyData(deviceID, &property, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value) != noErr {
            error = "静音操作失败。"
        }
        refresh()
    }

    func selectDevice(_ id: AudioDeviceID) {
        guard devices.contains(where: { $0.id == id }) else { return }
        var id = id
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        if AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil,
                                      UInt32(MemoryLayout.size(ofValue: id)), &id) != noErr {
            error = "无法切换输出设备。"
        }
        refresh()
    }
}
