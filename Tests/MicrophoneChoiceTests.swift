import CoreAudio
import XCTest

final class MicrophoneChoiceTests: XCTestCase {
    typealias Device = MicrophoneChoice.Device

    private func device(_ id: AudioDeviceID, bluetooth: Bool = false, builtIn: Bool = false, input: Bool = true,
                        running: Bool = false) -> Device {
        Device(id: id, hasInput: input, isBluetooth: bluetooth, runningSomewhere: running, isBuiltIn: builtIn)
    }

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
        let devices = [device(1, builtIn: true), device(2, bluetooth: true, running: true)]
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
}
