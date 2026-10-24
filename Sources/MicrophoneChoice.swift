import CoreAudio
import Foundation

/// Which input device speech input listens on. Recording from Bluetooth headphones switches them
/// to the hands-free profile, which stops their music and plays it again in low quality, so a
/// Bluetooth default input is avoided unless it is already recording for another app.
enum MicrophoneChoice {
    struct Device: Equatable {
        let id: AudioDeviceID
        let hasInput: Bool
        let isBluetooth: Bool
        /// Some process is recording from or playing to the device.
        let runningSomewhere: Bool
        let isBuiltIn: Bool
    }

    enum Rule: String {
        /// The default input is not Bluetooth.
        case defaultInput = "default"
        /// The default input is Bluetooth and already recording for another app.
        case alreadyRecording = "already-recording"
        /// The default input is Bluetooth, and the Mac's own microphone takes its place.
        case builtIn = "built-in"
        /// The default input is Bluetooth and the Mac has no microphone of its own.
        case bluetoothOnly = "bluetooth-only"
    }

    struct Choice: Equatable {
        let device: AudioDeviceID
        let rule: Rule
        /// Only the built-in rule picks a device other than the default input.
        var replacesDefault: Bool { rule == .builtIn }
    }

    static func choose(defaultInput: AudioDeviceID, among devices: [Device]) -> Choice {
        guard let current = devices.first(where: { $0.id == defaultInput }), current.isBluetooth else {
            return Choice(device: defaultInput, rule: .defaultInput)
        }
        if current.runningSomewhere { return Choice(device: defaultInput, rule: .alreadyRecording) }
        if let builtIn = devices.first(where: { $0.hasInput && $0.isBuiltIn && !$0.isBluetooth }) {
            return Choice(device: builtIn.id, rule: .builtIn)
        }
        return Choice(device: defaultInput, rule: .bluetoothOnly)
    }

    /// What the rule picks for the devices now, read from CoreAudio. Nil when the system has no
    /// default input, or the devices cannot be listed.
    static func current() -> Choice? {
        guard let defaultInput: AudioDeviceID = read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice),
              defaultInput != kAudioObjectUnknown,
              let ids: [AudioDeviceID] = readArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        else { return nil }
        return choose(defaultInput: defaultInput, among: ids.map(describe))
    }

    static func describe(_ id: AudioDeviceID) -> Device {
        let transport: UInt32 = read(id, kAudioDevicePropertyTransportType) ?? 0
        let running: UInt32 = read(id, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0
        let streams: [AudioStreamID]? = readArray(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        return Device(id: id, hasInput: !(streams ?? []).isEmpty,
                      isBluetooth: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                      runningSomewhere: running != 0,
                      isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn)
    }

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var address = address(selector, scope)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    private static func readArray<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [T]? {
        var address = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
        return [T](unsafeUninitializedCapacity: Int(size) / MemoryLayout<T>.stride) { buffer, count in
            var bytes = size
            let status = AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, buffer.baseAddress!)
            count = status == noErr ? Int(bytes) / MemoryLayout<T>.stride : 0
        }
    }
}
