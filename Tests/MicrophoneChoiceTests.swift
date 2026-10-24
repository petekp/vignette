import CoreAudio
import XCTest

final class MicrophoneChoiceTests: XCTestCase {
    typealias Device = MicrophoneChoice.Device

    private func device(_ id: AudioDeviceID, bluetooth: Bool = false, builtIn: Bool = false, input: Bool = true,
                        recording: Bool = false) -> Device {
        Device(id: id, hasInput: input, isBluetooth: bluetooth, recordingForAnotherApp: recording, isBuiltIn: builtIn)
    }

    private func process(_ pid: pid_t, running: Bool = true, input: [Int], output: [Int] = []) -> MicrophoneChoice.AudioProcess {
        .init(pid: pid, isRunningInput: running, inputDevices: input.map(AudioDeviceID.init), outputDevices: output.map(AudioDeviceID.init))
    }

    private let vignette: pid_t = 500

    private let builtIn = 1
    private let airpods = 2
    private let usb = 3

    private func choose(default id: Int, _ devices: [Device]) -> MicrophoneChoice.Choice {
        MicrophoneChoice.choose(defaultInput: AudioDeviceID(id), among: devices)
    }

    func testUsesDefaultInputThatIsNotBluetooth() {
        let devices = [device(1, builtIn: true), device(3), device(2, bluetooth: true)]
        XCTAssertEqual(choose(default: usb, devices), .init(device: 3, rule: .defaultInput))
    }

    func testUsesBluetoothDefaultAlreadyRecordingForAnotherApp() {
        let devices = [device(1, builtIn: true), device(2, bluetooth: true, recording: true)]
        XCTAssertEqual(choose(default: airpods, devices), .init(device: 2, rule: .alreadyRecording))
    }

    func testPrefersBuiltInMicrophoneOverIdleBluetoothDefault() {
        let devices = [device(1, builtIn: true), device(2, bluetooth: true)]
        XCTAssertEqual(choose(default: airpods, devices), .init(device: 1, rule: .builtIn))
    }

    func testKeepsBluetoothDefaultWhenMacHasNoBuiltInMicrophone() {
        let devices = [device(1, builtIn: true, input: false), device(2, bluetooth: true)]
        XCTAssertEqual(choose(default: airpods, devices), .init(device: 2, rule: .bluetoothOnly))
    }

    func testFallsBackToDefaultWhenItIsNotListed() {
        XCTAssertEqual(choose(default: 9, [device(1, builtIn: true)]), .init(device: 9, rule: .defaultInput))
    }

    func testADeviceAnotherAppRecordsFromCountsAsRecording() {
        let call = process(7, input: [airpods], output: [4])
        XCTAssertEqual(MicrophoneChoice.recordedByOtherApps([call], own: vignette), [2])
    }

    func testAnAppListingOneDeviceAsBothInputAndOutputDoesNotCount() {
        let headset = 5
        let playing = process(7, input: [headset], output: [headset])
        XCTAssertEqual(MicrophoneChoice.recordedByOtherApps([playing], own: vignette), [])
    }

    func testVignetteAndAppsNotRunningInputDoNotCount() {
        let processes = [process(vignette, input: [airpods]), process(7, running: false, input: [airpods])]
        XCTAssertEqual(MicrophoneChoice.recordedByOtherApps(processes, own: vignette), [])
    }
}
