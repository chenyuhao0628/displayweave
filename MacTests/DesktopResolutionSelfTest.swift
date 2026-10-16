import Foundation

@main enum DesktopResolutionSelfTest {
    static func main() throws {
        let retina = DesktopResolutionPolicy.geometry(.native, nativeWidth: 5120,
            nativeHeight: 2880, nativePointsWide: 2560, nativePointsHigh: 1440, backingScale: 2)
        precondition(retina.pointsWide == 2560 && retina.pixelsWide == 5120)
        let fhd = DesktopResolutionPolicy.geometry(.fullHD, nativeWidth: 5120,
            nativeHeight: 2880, backingScale: 2)
        precondition(fhd.pixelsWide == 1920 && fhd.pixelsHigh == 1080)
        precondition(fhd.pointsWide == 960 && fhd.pointsHigh == 540)
        let portrait = DesktopResolutionPolicy.geometry(.ultraHD, nativeWidth: 1080,
            nativeHeight: 1920, backingScale: 1)
        precondition(portrait.pointsWide == 2160 && portrait.pointsHigh == 3840)
        let raster = DesktopResolutionPolicy.raster(portrait, qualityScale: 1,
            maxWidth: 1080, maxHeight: 1920)
        precondition(raster.width == 1080 && raster.height == 1920,
                     "decoder limit must not silently change desktop geometry")
        let scaled = DesktopResolutionPolicy.raster(fhd, qualityScale: 0.75,
            maxWidth: 4096, maxHeight: 2304)
        precondition(scaled.width == 1440 && scaled.height == 810)
        let invalid = DesktopResolutionPolicy.geometry(.native, nativeWidth: Int.max,
            nativeHeight: -1, backingScale: 99)
        precondition(invalid.pixelsWide <= 16384 && invalid.pixelsHigh >= 4)

        let name = "DesktopResolutionSelfTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = StreamSettings.load(from: defaults)
        precondition(settings.desktopResolutions.resolution(for: "A") == .native)
        settings.desktopResolutions.set(.fullHD, for: "A")
        settings.desktopResolutions.set(.ultraHD, for: "B")
        settings.save(to: defaults)
        let loaded = StreamSettings.load(from: defaults)
        precondition(loaded.desktopResolutions.resolution(for: "A") == .fullHD)
        precondition(loaded.desktopResolutions.resolution(for: "B") == .ultraHD)
        settings.desktopResolutions.set(.native, for: "A")
        precondition(settings.desktopResolutions.resolution(for: "A") == .native)
        precondition(settings.desktopResolutions.resolution(for: "B") == .ultraHD)
        let invalidPreferences = DesktopResolutionPreferences(stored: ["": "fullHD",
            String(repeating: "x", count: 257): "fullHD", "bad": "unknown"])
        precondition(invalidPreferences.stored.isEmpty)
        for i in 0..<256 { settings.desktopResolutions.set(.quadHD, for: "device-\(i)") }
        precondition(settings.desktopResolutions.stored.count <= 128)

        let info = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":5120,"pixelsHigh":2880,"scale":2,"device":"Mac","id":"A","videoCaps":[{"codec":"h264","maxWidth":1280,"maxHeight":720,"maxFrameRate":60}]}"#.utf8))
        var selected = loaded
        selected.quality = .high
        let plan = MacReceiverPolicy.plan(info: info, settings: selected)
        precondition(plan.pointsWide == 960 && plan.pointsHigh == 540)
        precondition(plan.width == 1280 && plan.height == 720)
        let mirror = MacReceiverPolicy.plan(info: info, settings: selected,
            sourceWidth: 1000, sourceHeight: 800)
        precondition(mirror.width == 900 && mirror.height == 720,
                     "mirroring must use the physical source aspect ratio")
        print("Desktop resolution geometry, bounds, per-device persistence and encoder limits PASS")
    }
}
