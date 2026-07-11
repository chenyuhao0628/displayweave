import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

private final class FakeAdbRunner: AndroidAdbProcessRunning, @unchecked Sendable {
    var calls: [(URL, [String])] = []
    var result = AndroidAdbCommandResult(stdout: "List of devices attached\n",
                                         stderr: "", exitCode: 0)

    func run(executable: URL, arguments: [String], timeout: Duration) async throws
        -> AndroidAdbCommandResult {
        calls.append((executable, arguments))
        return result
    }
}

@main
struct AndroidAdbSelfTest {
    static func main() async throws {
        let output = """
        List of devices attached
        R58M123 device product:foo model:Pixel_8 transport_id:1
        ABC unauthorized usb:1-2 transport_id:2
        XYZ offline usb:1-3 transport_id:3

        """

        let devices = AndroidAdbDeviceList.parse(output)
        expect(devices.count == 3, "all ADB device rows should be parsed")
        expect(devices[0] == AndroidAdbDevice(serial: "R58M123", state: .device,
                                              model: "Pixel 8", connectionKind: .unknown,
                                              product: "foo"),
               "ready device should preserve serial and normalize model name")
        expect(devices[1].serial == "ABC" && devices[1].state == .unauthorized,
               "unauthorized device should be classified")
        expect(devices[1].connectionKind == .usb,
               "unauthorized USB devices must remain identifiable as wired")
        expect(devices[2].serial == "XYZ" && devices[2].state == .offline,
               "offline device should be classified")

        let dualEndpointOutput = """
        List of devices attached
        HA2AE8R5 device usb:1-2 product:OPD2413 model:OPD2413 device:OP615EL1 transport_id:639
        adb-HA2AE8R5-C1o9Bn._adb-tls-connect._tcp device product:OPD2413 model:OPD2413 device:OP615EL1 transport_id:2

        """
        let dualEndpoints = AndroidAdbDeviceList.parse(dualEndpointOutput)
        expect(dualEndpoints.map(\.connectionKind) == [.usb, .wirelessDebugging],
               "ADB rows must preserve their physical connection kind")
        expect(AndroidAdbDeviceSelection.usbDevices(from: dualEndpoints).map(\.serial)
               == ["HA2AE8R5"],
               "wireless debugging must never create a second AdbUsbTransport session")

        let twoUsbOutput = """
        List of devices attached
        USB-A device usb:1-2 product:a model:Tablet_A device:a transport_id:1
        USB-B device usb:1-3 product:b model:Tablet_B device:b transport_id:2

        """
        let twoUsb = AndroidAdbDeviceSelection.usbDevices(
            from: AndroidAdbDeviceList.parse(twoUsbOutput))
        expect(twoUsb.map(\.serial) == ["USB-A", "USB-B"],
               "two physical USB devices must remain independently connectable")
        expect(twoUsb.map(\.product) == ["a", "b"] && twoUsb.map(\.device) == ["a", "b"],
               "ADB product and device metadata should be preserved")

        expect(AndroidAdbFailure.executableNotFound(["/missing/adb"])
            .localizedDescription.contains("ADB"),
               "missing executable should identify ADB")
        expect(AndroidAdbFailure.noDevices.localizedDescription.contains("未检测到 Android 设备"),
               "empty device list should explain that no Android device was found")
        expect(AndroidAdbFailure.unauthorized("ABC").localizedDescription.contains("允许当前 Mac"),
               "unauthorized state should explain the device authorization action")
        expect(AndroidAdbFailure.offline("XYZ").localizedDescription.contains("离线"),
               "offline state should be explicit")
        expect(AndroidAdbFailure.multipleDevices(["A", "B"])
            .localizedDescription.contains("选择目标设备"),
               "multiple devices should request an explicit selection")

        let candidates = Set([
            "/configured/adb", "/path/bin/adb", "/android-home/platform-tools/adb",
            "/sdk-root/platform-tools/adb", "/Users/test/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb", "/usr/local/bin/adb",
        ])
        let environment = [
            "PATH": "/path/bin:/other/bin",
            "ANDROID_HOME": "/android-home",
            "ANDROID_SDK_ROOT": "/sdk-root",
        ]
        let selected = AndroidAdbExecutableResolver.resolve(
            configuredPath: "/configured/adb", environment: environment,
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            fileExists: { candidates.contains($0.path) },
            isExecutable: { candidates.contains($0.path) })
        expect(selected?.path == "/configured/adb",
               "configured ADB path should have highest priority")

        let pathSelected = AndroidAdbExecutableResolver.resolve(
            configuredPath: nil, environment: environment,
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            fileExists: { candidates.contains($0.path) },
            isExecutable: { candidates.contains($0.path) })
        expect(pathSelected?.path == "/path/bin/adb", "PATH should precede SDK locations")

        let runner = FakeAdbRunner()
        let client = AndroidAdbClient(executable: URL(fileURLWithPath: "/configured/adb"),
                                      runner: runner)
        _ = try await client.devices()
        expect(runner.calls.last?.1 == ["devices", "-l"],
               "device discovery should call adb devices -l")
        _ = try await client.run(serial: "R58M123", arguments: ["forward", "--list"])
        expect(runner.calls.last?.1 == ["-s", "R58M123", "forward", "--list"],
               "device commands should pass serial as a separate argument")

        let processRunner = FoundationAdbProcessRunner()
        let printed = try await processRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", "hello"], timeout: .seconds(2))
        expect(printed.stdout == "hello" && printed.exitCode == 0,
               "production runner should capture stdout without a shell")

        do {
            _ = try await processRunner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["1"], timeout: .milliseconds(20))
            fatalError("production runner should time out a long command")
        } catch AndroidAdbFailure.timedOut {
            // Expected.
        }

        let missingPresentation = AndroidAdbPresentation.make(
            executableFound: false, devices: [])
        expect(missingPresentation.message.contains("未找到 ADB")
               && missingPresentation.connectableSerials.isEmpty,
               "missing ADB should be actionable and disable connection")
        let emptyPresentation = AndroidAdbPresentation.make(
            executableFound: true, devices: [])
        expect(emptyPresentation.message == "未检测到 Android 设备",
               "empty ADB list should show the required message")
        let unauthorizedPresentation = AndroidAdbPresentation.make(
            executableFound: true,
            devices: [AndroidAdbDevice(serial: "U", state: .unauthorized, model: nil)])
        expect(unauthorizedPresentation.message.contains("允许当前 Mac"),
               "unauthorized device should show the authorization action")
        let offlinePresentation = AndroidAdbPresentation.make(
            executableFound: true,
            devices: [AndroidAdbDevice(serial: "O", state: .offline, model: nil)])
        expect(offlinePresentation.message.contains("离线"),
               "offline device should be identified")
        let readyPresentation = AndroidAdbPresentation.make(
            executableFound: true,
            devices: [AndroidAdbDevice(serial: "A", state: .device, model: "Pixel")])
        expect(readyPresentation.connectableSerials == ["A"],
               "ready device should enable its connection")
        let multiplePresentation = AndroidAdbPresentation.make(
            executableFound: true,
            devices: [AndroidAdbDevice(serial: "A", state: .device, model: nil),
                      AndroidAdbDevice(serial: "B", state: .device, model: nil)])
        expect(multiplePresentation.message.contains("选择目标设备")
               && multiplePresentation.connectableSerials == ["A", "B"],
               "multiple devices should remain individually selectable")

        print("AndroidAdbSelfTest PASS")
    }
}
