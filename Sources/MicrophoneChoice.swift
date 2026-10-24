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
        /// Another app is recording from the device (`recordedByOtherApps`).
        let recordingForAnotherApp: Bool
        let isBuiltIn: Bool
    }

    /// One app connected to CoreAudio, from its process object.
    struct AudioProcess: Equatable {
        let pid: pid_t
        let isRunningInput: Bool
        let inputDevices: [AudioDeviceID]
        let outputDevices: [AudioDeviceID]
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
        if current.recordingForAnotherApp { return Choice(device: defaultInput, rule: .alreadyRecording) }
        if let builtIn = devices.first(where: { $0.hasInput && $0.isBuiltIn && !$0.isBluetooth }) {
            return Choice(device: builtIn.id, rule: .builtIn)
        }
        return Choice(device: defaultInput, rule: .bluetoothOnly)
    }

    /// The devices other apps are recording from: an app other than `own` that is running input
    /// and lists the device among its input devices but not among its output devices. CoreAudio's
    /// input list can name a device the app only plays to: on 2026-10-23 CoreSpeech, recording,
    /// listed the MacBook's speakers, which have no input. So a headset that is one device for both,
    /// listed both ways, never counts, and the rule takes the built-in microphone rather than risk
    /// stopping its music.
    static func recordedByOtherApps(_ processes: [AudioProcess], own: pid_t) -> Set<AudioDeviceID> {
        Set(processes.filter { $0.pid != own && $0.isRunningInput }.flatMap { process in
            process.inputDevices.filter { !process.outputDevices.contains($0) }
        })
    }

    /// What the rule picks for the devices now, read from CoreAudio. Nil when the system has no
    /// default input, or the devices cannot be listed. Apps that cannot be listed count as recording
    /// from nothing.
    static func current() -> Choice? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let defaultInput: AudioDeviceID = read(system, kAudioHardwarePropertyDefaultInputDevice),
              defaultInput != kAudioObjectUnknown,
              let ids: [AudioDeviceID] = readArray(system, kAudioHardwarePropertyDevices)
        else { return nil }
        let processes: [AudioObjectID] = readArray(system, kAudioHardwarePropertyProcessObjectList) ?? []
        let recorded = recordedByOtherApps(processes.compactMap(process), own: getpid())
        return choose(defaultInput: defaultInput, among: ids.map { describe($0, recorded: recorded) })
    }

    static func describe(_ id: AudioDeviceID, recorded: Set<AudioDeviceID>) -> Device {
        let transport: UInt32 = read(id, kAudioDevicePropertyTransportType) ?? 0
        let streams: [AudioStreamID]? = readArray(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        return Device(id: id, hasInput: !(streams ?? []).isEmpty,
                      isBluetooth: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                      recordingForAnotherApp: recorded.contains(id),
                      isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn)
    }

    static func process(_ id: AudioObjectID) -> AudioProcess? {
        guard let pid: pid_t = read(id, kAudioProcessPropertyPID) else { return nil }
        let running: UInt32 = read(id, kAudioProcessPropertyIsRunningInput) ?? 0
        return AudioProcess(pid: pid, isRunningInput: running != 0,
                            inputDevices: readArray(id, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput) ?? [],
                            outputDevices: readArray(id, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput) ?? [])
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
