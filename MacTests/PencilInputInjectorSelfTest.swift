import Foundation
import CoreGraphics

@main struct PencilInputInjectorSelfTest {
    static func main() {
        var events: [CGEvent] = []
        let injector = InputInjector(displayID: 0, boundsProvider: { CGRect(x: -100, y: 20, width: 1000, height: 500) }, eventSink: { events.append($0) })
        func sample(_ phase: PencilSample.Phase) -> PencilSample {
            PencilSample(phase: phase, x: 0.2, y: 0.6, pressure: 0.5, azimuth: 0, altitude: .pi / 4)!
        }
        injector.handleTouch(phase: "began", x: 0.1, y: 0.1)
        injector.handlePencil(sample(.down))
        precondition(events.map(\.type) == [.leftMouseDown, .leftMouseUp, .tabletProximity, .leftMouseDown])
        let down = events.last!
        precondition(down.location == CGPoint(x: 100, y: 320))
        precondition(down.getIntegerValueField(.mouseEventSubtype) == Int64(CGEventMouseSubtype.tabletPoint.rawValue))
        // CoreGraphics stores mouse pressure at 8-bit precision.
        precondition(abs(down.getDoubleValueField(.mouseEventPressure) - 0.5) <= 1.0 / 255)
        precondition(abs(down.getDoubleValueField(.tabletEventTiltX) - 0.5) < 0.001)
        precondition(abs(down.getDoubleValueField(.tabletEventTiltY)) < 0.001)
        precondition(down.getIntegerValueField(.tabletEventPointPressure) == 32768)
        injector.handlePencil(sample(.move))
        precondition(events.last!.type == .leftMouseDragged)
        let count = events.count
        injector.handleTouch(phase: "began", x: 0.3, y: 0.3)
        injector.handleScroll(dx: 10, dy: 10)
        precondition(events.count == count, "palm changed active pen stroke")
        injector.cancelPress()
        precondition(events.suffix(2).map(\.type) == [.leftMouseUp, .tabletProximity])
        precondition(events[events.count-2].getDoubleValueField(.mouseEventPressure) == 0)
        precondition(events.last!.getIntegerValueField(.tabletProximityEventEnterProximity) == 0)
        let cancelled = events.count
        injector.cancelPress()
        injector.handlePencil(sample(.up))
        precondition(events.count == cancelled)
        injector.handlePencil(sample(.hover))
        precondition(events.last!.type == .mouseMoved && events.last!.getDoubleValueField(.mouseEventPressure) == 0)
        injector.handleProximity(entering: false, x: 0.2, y: 0.6)
        precondition(events.last!.type == .tabletProximity)
        injector.handlePencil(sample(.down))
        injector.handleProximity(entering: false, x: 0.2, y: 0.6)
        precondition(events.suffix(2).map(\.type) == [.leftMouseUp, .tabletProximity])
        print("Pencil native events: pressure, tilt, coordinate mapping, palm isolation and idempotent cleanup PASS")
    }
}
