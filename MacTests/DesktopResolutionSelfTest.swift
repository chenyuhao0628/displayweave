import Foundation
import CoreGraphics

@main enum DesktopResolutionSelfTest {
    static func main() throws {
        let androidMirror = DesktopResolutionPolicy.mirrorRaster(sourceWidth: 5120, sourceHeight: 2880,
            qualityScale: 1, maxWidth: 1920, maxHeight: 1200)
        precondition(androidMirror.width == 1920 && androidMirror.height == 1080)
        let portraitMirror = DesktopResolutionPolicy.mirrorRaster(sourceWidth: 3840, sourceHeight: 2160,
            qualityScale: 1, maxWidth: 1080, maxHeight: 2340)
        precondition(portraitMirror.width <= 1080 && portraitMirror.height <= 2340)
        let retina = DesktopResolutionPolicy.geometry(.native, nativeWidth: 5120,
            nativeHeight: 2880, nativePointsWide: 2560, nativePointsHigh: 1440, backingScale: 2)
        precondition(retina.pointsWide == 2560 && retina.pixelsWide == 5120)
        for (raw, width, height) in [("iMac4K", 4096, 2304), ("iMac4_5K", 4480, 2520), ("iMac5K", 5120, 2880)] {
            guard let selection = DesktopResolution(rawValue: raw) else {
                fatalError("missing iMac desktop preset: \(raw)")
            }
            let geometry = DesktopResolutionPolicy.geometry(selection, nativeWidth: width,
                nativeHeight: height, backingScale: 2)
            precondition(geometry.pointsWide == width / 2 && geometry.pointsHigh == height / 2)
            precondition(geometry.pixelsWide == width && geometry.pixelsHigh == height)
            let portrait = DesktopResolutionPolicy.geometry(selection, nativeWidth: height,
                nativeHeight: width, backingScale: 2)
            precondition(portrait.pointsWide == height / 2 && portrait.pointsHigh == width / 2)
            let limited = DesktopResolutionPolicy.raster(geometry, qualityScale: 0.5,
                maxWidth: 4096, maxHeight: 2304)
            precondition(limited.width == width / 2 && geometry.pointsWide == width / 2,
                         "lowering transmission quality must not resize the desktop")
        }
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

        let main = DesktopMatchReference(id: 1, bounds: CGRect(x: 0, y: 0, width: 2048, height: 1152),
            isMain: true, isBuiltIn: true, eligible: true, physicalSize: .init(width: 600, height: 338))
        let neighbour = DesktopMatchReference(id: 2, bounds: CGRect(x: 2048, y: 0, width: 2048, height: 1152),
            isMain: false, isBuiltIn: false, eligible: true, physicalSize: .init(width: 600, height: 338))
        let virtual = DesktopMatchReference(id: 3, bounds: CGRect(x: 4096, y: 0, width: 1280, height: 720),
            isMain: false, isBuiltIn: false, eligible: false, physicalSize: nil)
        let saved = CGRect(x: 4096, y: 0, width: 1280, height: 720)
        precondition(DesktopMatchPolicy.reference(from: [main, neighbour, virtual], adjacentTo: saved)?.id == 2)
        precondition(DesktopMatchPolicy.reference(from: [virtual, neighbour, main], adjacentTo: nil)?.id == 1)
        precondition(DesktopMatchPolicy.reference(from: [virtual], adjacentTo: saved) == nil)

        let receiver = DesktopGeometry(pointsWide: 2560, pointsHigh: 1440, scale: 2)
        let matching = DesktopMatchPolicy.match(receiver: receiver, reference: main,
            receiverSize: .init(width: 598, height: 337))
        precondition(matching.geometry == .init(pointsWide: 2048, pointsHigh: 1152, scale: 2))
        precondition(matching.basis == .physical)
        let unknownSize = DesktopMatchPolicy.match(receiver: receiver, reference: main, receiverSize: nil)
        precondition(unknownSize.geometry == matching.geometry && unknownSize.basis == .proportional)
        let smallReceiver = DesktopMatchPolicy.match(receiver: receiver, reference: main,
            receiverSize: .init(width: 300, height: 169))
        precondition(smallReceiver.geometry == .init(pointsWide: 1024, pointsHigh: 576, scale: 2))
        let tall = DesktopMatchPolicy.match(receiver: .init(pointsWide: 1440, pointsHigh: 2560, scale: 2),
            reference: main, receiverSize: nil)
        precondition(tall.geometry == .init(pointsWide: 1152, pointsHigh: 2048, scale: 2))
        let oneX = DesktopMatchPolicy.match(receiver: .init(pointsWide: 2560, pointsHigh: 1440, scale: 1),
            reference: main, receiverSize: nil)
        precondition(oneX.geometry == .init(pointsWide: 2048, pointsHigh: 1152, scale: 2),
                     "a smaller logical desktop needs more backing detail on a 1x receiver")
        let oneXEnough = DesktopMatchPolicy.match(receiver: .init(pointsWide: 1920, pointsHigh: 1080, scale: 1),
            reference: main, receiverSize: nil)
        precondition(oneXEnough.geometry == .init(pointsWide: 2048, pointsHigh: 1152, scale: 1))
        let fallback = DesktopMatchPolicy.match(receiver: receiver, reference: nil, receiverSize: nil)
        precondition(fallback.geometry == receiver && fallback.basis == .receiver)
        let huge = DesktopMatchPolicy.match(receiver: .init(pointsWide: 8192, pointsHigh: 2, scale: 2),
            reference: main, receiverSize: .init(width: 2000, height: 50))
        precondition(huge.geometry.pixelsWide <= 16384 && huge.geometry.pixelsHigh <= 16384)
        precondition(huge.geometry.pixelsWide * huge.geometry.pixelsHigh <= 67_108_864)
        precondition(DesktopPhysicalSize.validated(width: 600, height: 338, pointsWide: 2048,
            pointsHigh: 1152) != nil)
        let rotatedSize = DesktopPhysicalSize.validated(width: 600, height: 338, pointsWide: 1152,
            pointsHigh: 2048)
        precondition(rotatedSize == .init(width: 338, height: 600))
        precondition(DesktopPhysicalSize.validated(width: 2048 * 25.4 / 72, height: 1152 * 25.4 / 72,
            pointsWide: 2048, pointsHigh: 1152) == nil, "72 dpi fallback is not a measurement")
        precondition(DesktopPhysicalSize.validated(width: .nan, height: 338, pointsWide: 2048,
            pointsHigh: 1152) == nil)
        precondition(DesktopPhysicalSize.validated(width: 10, height: 2000, pointsWide: 2048,
            pointsHigh: 1152) == nil)

        let name = "DesktopResolutionSelfTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = StreamSettings.load(from: defaults)
        precondition(settings.desktopResolutions.resolution(for: "A") == .automatic)
        precondition(settings.desktopResolutions.resolution(for: nil) == .native)
        defaults.set(["connection"], forKey: "wifiRemembered")
        precondition(StreamSettings.load(from: defaults).desktopResolutions.resolution(for: "A") == .automatic,
                     "a first connection must not turn a new installation into a legacy one on relaunch")
        precondition(settings.adaptEncoderLoad)
        settings.adaptEncoderLoad = false
        settings.desktopResolutions.set(.fullHD, for: "A")
        settings.desktopResolutions.set(.ultraHD, for: "B")
        settings.save(to: defaults)
        let loaded = StreamSettings.load(from: defaults)
        precondition(!loaded.adaptEncoderLoad)
        precondition(loaded.desktopResolutions.resolution(for: "A") == .fullHD)
        precondition(loaded.desktopResolutions.resolution(for: "B") == .ultraHD)
        settings.desktopResolutions.set(.native, for: "A")
        precondition(settings.desktopResolutions.resolution(for: "A") == .native)
        precondition(settings.desktopResolutions.resolution(for: "B") == .ultraHD)
        settings.save(to: defaults)
        precondition(StreamSettings.load(from: defaults).desktopResolutions.resolution(for: "A") == .native)
        settings.desktopResolutions.set(.automatic, for: "A")
        precondition(settings.desktopResolutions.resolution(for: "A") == .automatic)
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
        selected.desktopResolutions.set(.automatic, for: "A")
        let automatic = MacReceiverPolicy.plan(info: info, settings: selected, automaticReference: main)
        precondition(automatic.pointsWide == 2048 && automatic.pointsHigh == 1152)
        precondition(automatic.width == 1280 && automatic.height == 720,
                     "automatic desktop geometry must not evade a receiver's video envelope")
        let physicalInfo = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":5120,"pixelsHigh":2880,"scale":2,"device":"Mac","id":"A","panel":{"pixelsWide":5120,"pixelsHigh":2880,"scale":2,"pointsWide":2560,"pointsHigh":1440,"millimetersWide":300,"millimetersHigh":169}}"#.utf8))
        let physicalPlan = MacReceiverPolicy.plan(info: physicalInfo, settings: selected, automaticReference: main)
        precondition(physicalPlan.pointsWide == 1024 && physicalPlan.pointsHigh == 576)
        precondition(physicalInfo.hasValidGeometry && MacReceiverPolicy.physicalSize(panel: physicalInfo.panel) != nil)
        let malformedPhysical = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":5120,"pixelsHigh":2880,"scale":2,"device":"Mac","id":"A","panel":{"pixelsWide":5120,"pixelsHigh":2880,"scale":2,"millimetersWide":-1,"millimetersHigh":169}}"#.utf8))
        precondition(malformedPhysical.hasValidGeometry && MacReceiverPolicy.physicalSize(panel: malformedPhysical.panel) == nil)
        precondition(MacReceiverPolicy.plan(info: malformedPhysical, settings: selected,
            automaticReference: main).pointsWide == 2048, "invalid optional millimeters must fall back")
        let wrongPhysicalType = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":5120,"pixelsHigh":2880,"scale":2,"device":"Mac","id":"A","panel":{"pixelsWide":5120,"pixelsHigh":2880,"scale":2,"millimetersWide":"unknown","millimetersHigh":999999999999999999999999}}"#.utf8))
        precondition(wrongPhysicalType.hasValidGeometry && MacReceiverPolicy.physicalSize(panel: wrongPhysicalType.panel) == nil,
                     "optional extension fields must not prevent legacy geometry negotiation")

        let legacyName = "\(name).legacy"
        let legacy = UserDefaults(suiteName: legacyName)!
        defer { legacy.removePersistentDomain(forName: legacyName) }
        legacy.set(["saved": "iMac4K"], forKey: "desktopResolutions.v1")
        var migrated = StreamSettings.load(from: legacy)
        precondition(migrated.desktopResolutions.resolution(for: "saved") == .iMac4K)
        precondition(migrated.desktopResolutions.resolution(for: "unspecified") == .native)
        migrated.desktopResolutions.set(.automatic, for: "unspecified")
        migrated.save(to: legacy)
        let reloaded = StreamSettings.load(from: legacy)
        precondition(reloaded.desktopResolutions.resolution(for: "saved") == .iMac4K)
        precondition(reloaded.desktopResolutions.resolution(for: "unspecified") == .automatic)
        precondition(reloaded.desktopResolutions.resolution(for: "another") == .native)
        let legacyWithoutMap = UserDefaults(suiteName: "\(name).old-settings")!
        defer { legacyWithoutMap.removePersistentDomain(forName: "\(name).old-settings") }
        legacyWithoutMap.set("balanced", forKey: "quality")
        precondition(StreamSettings.load(from: legacyWithoutMap).desktopResolutions.resolution(for: "A") == .native)
        print("Desktop resolution geometry, bounds, per-device persistence and encoder limits PASS")
    }
}
