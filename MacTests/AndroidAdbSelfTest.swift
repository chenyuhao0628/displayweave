import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct AndroidAdbSelfTest {
    static func main() {
        let output = """
        List of devices attached
        R58M123 device product:foo model:Pixel_8 transport_id:1
        ABC unauthorized usb:1-2 transport_id:2
        XYZ offline usb:1-3 transport_id:3

        """

        let devices = AndroidAdbDeviceList.parse(output)
        expect(devices.count == 3, "all ADB device rows should be parsed")
        expect(devices[0] == AndroidAdbDevice(serial: "R58M123", state: .device,
                                              model: "Pixel 8"),
               "ready device should preserve serial and normalize model name")
        expect(devices[1].serial == "ABC" && devices[1].state == .unauthorized,
               "unauthorized device should be classified")
        expect(devices[2].serial == "XYZ" && devices[2].state == .offline,
               "offline device should be classified")

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

        print("AndroidAdbSelfTest PASS")
    }
}
