import SwiftUI
import AVFoundation
import UIKit
import Combine

// MARK: - Video layer host view

/// UIView whose backing layer is the AVSampleBufferDisplayLayer.
/// Forwards touches as normalized video-space coordinates (touchscreen mode).
struct VideoLayerView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer
    let receiver: PhoneReceiver
    let useMetal: Bool

    func makeUIView(context: Context) -> VideoView { makeVideoView() }

    func makeVideoView() -> VideoView {
        let view = VideoView()
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true
        receiver.claimPresentation(view.presentationID) { [weak view] in view?.retirePresentation() }
        view.receiver = receiver

        Log.info("video view: metal=\(useMetal)")
        if useMetal, let renderer = MetalVideoRenderer() {
            Log.info("metal renderer active")
            view.metalRenderer = renderer
            view.layer.addSublayer(renderer.metalLayer)
            receiver.onDecodedFrame = { [weak renderer, weak receiver] pixelBuffer, captureMs in
                guard let receiver else { return }
                renderer?.render(pixelBuffer, captureMs: captureMs, generation: receiver.inputGeneration)
            }
            renderer.onPresented = { [weak receiver] presentedTime, captureMs, generation in
                receiver?.recordPresented(presentedTime: presentedTime, captureMs: captureMs, generation: generation)
            }
        } else {
            receiver.onDecodedFrame = nil   // route frames back to AVSBDL
            view.sampleBufferLayer = displayLayer
            displayLayer.frame = view.bounds
            view.layer.addSublayer(displayLayer)
        }

        let pan = UIPanGestureRecognizer(target: view, action: #selector(VideoView.didTwoFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addGestureRecognizer(pan)
        let hover = UIHoverGestureRecognizer(target: view, action: #selector(VideoView.didPencilHover(_:)))
        hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        view.addGestureRecognizer(hover)
        let pencil = UIPencilInteraction()
        pencil.delegate = view
        view.addInteraction(pencil)
        receiver.onInputReset = { [weak view] in view?.resetInput() }
        receiver.onPencilToolChange = { [weak view] in view?.cancelPress() }

        // Local cursor echo: position updates ride the ~2ms control path
        // instead of the ~30ms video path, so the pointer feels native.
        receiver.onCursor = { [weak view] x, y, visible in
            view?.moveCursor(x: x, y: y, visible: visible)
        }
        receiver.onCursorImage = { [weak view] image, anchor, normSize in
            view?.setCursorSprite(image, anchor: anchor, normSize: normSize)
        }
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        // videoSize arrives after the format description — re-fit the layers.
        uiView.setNeedsLayout()
        uiView.updateDisplayLink()
    }

    static func dismantleUIView(_ uiView: VideoView, coordinator: ()) {
        uiView.receiver?.releasePresentation(uiView.presentationID)
        uiView.retirePresentation()
    }

    final class VideoView: UIView, UIPencilInteractionDelegate {
        let presentationID = UUID()
        weak var receiver: PhoneReceiver?
        weak var sampleBufferLayer: AVSampleBufferDisplayLayer?

        func retirePresentation() {
            cancelPress()
            stopDisplayLink()
            metalRenderer?.onPresented = nil
            metalRenderer?.metalLayer.removeFromSuperlayer()
            metalRenderer = nil
            if sampleBufferLayer?.superlayer === layer { sampleBufferLayer?.removeFromSuperlayer() }
            sampleBufferLayer = nil
            receiver = nil
        }

        var metalRenderer: MetalVideoRenderer?
        private var displayLink: CADisplayLink?
        private var cursorDirty = false
        private final class DisplayLinkTarget: NSObject {
            weak var view: VideoView?
            @objc func tick(_ link: CADisplayLink) { view?.presentCursor() }
        }
        private let displayLinkTarget = DisplayLinkTarget()

        func updateDisplayLink() {
            guard window != nil, receiver?.connected == true else { stopDisplayLink(); return }
            if displayLink == nil {
                displayLinkTarget.view = self
                let link = CADisplayLink(target: displayLinkTarget, selector: #selector(DisplayLinkTarget.tick(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            let maximum = min(window?.screen.maximumFramesPerSecond ?? 60, receiver?.requestedFps ?? 60)
            let fps = Float(max(1, maximum))
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, fps), maximum: fps, preferred: fps)
        }

        func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        private func presentCursor() {
            guard cursorDirty else { return }
            cursorDirty = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cursorLayer.isHidden = !cursorVisible || cursorLayer.contents == nil
            updateCursorLayout()
            CATransaction.commit()
        }

        private let cursorLayer: CALayer = {
            let layer = CALayer()
            layer.isHidden = true
            layer.zPosition = 10
            // Position updates arrive at 120Hz — implicit animations would
            // smear the cursor behind every move.
            layer.actions = ["position": NSNull(), "contents": NSNull(),
                             "bounds": NSNull(), "hidden": NSNull()]
            return layer
        }()
        private var cursorNormSize = CGSize.zero
        private var cursorNorm = CGPoint(x: 0.5, y: 0.5)
        private var cursorVisible = false

        private var lastLoggedLayout = ""

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let renderer = metalRenderer {
                // The metal layer scales its drawable to fill its frame, so
                // the frame itself must be the aspect-fit rect.
                renderer.metalLayer.frame = videoRect() ?? bounds
            } else {
                // AVSBDL aspect-fits internally (videoGravity) — full bounds.
                layer.sublayers?.first?.frame = bounds
            }
            if cursorLayer.superlayer == nil { layer.addSublayer(cursorLayer) }
            updateCursorLayout()
            CATransaction.commit()
            // Rotation diagnostics — one line per layout change.
            let video = receiver?.videoSize ?? .zero
            let line = "layout: bounds=\(Int(bounds.width))x\(Int(bounds.height))"
                + " video=\(Int(video.width))x\(Int(video.height))"
                + " layer=\(Int(layer.sublayers?.first?.frame.width ?? -1))x\(Int(layer.sublayers?.first?.frame.height ?? -1))"
            if line != lastLoggedLayout {
                lastLoggedLayout = line
                Log.info(line)
            }
        }

        /// Aspect-fit rect of the video inside the view (inverse of normalized()).
        private func videoRect() -> CGRect? {
            guard let video = receiver?.videoSize, video != .zero,
                  bounds.width > 0, bounds.height > 0 else { return nil }
            let scale = min(bounds.width / video.width, bounds.height / video.height)
            let size = CGSize(width: video.width * scale, height: video.height * scale)
            return CGRect(x: (bounds.width - size.width) / 2,
                          y: (bounds.height - size.height) / 2,
                          width: size.width, height: size.height)
        }

        func moveCursor(x: Double, y: Double, visible: Bool) {
            cursorNorm = CGPoint(x: x, y: y)
            cursorVisible = visible
            cursorDirty = true
            if displayLink == nil { presentCursor() }
        }

        func setCursorSprite(_ image: UIImage, anchor: CGPoint, normSize: CGSize) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cursorLayer.contents = image.cgImage
            cursorLayer.anchorPoint = anchor
            cursorNormSize = normSize
            cursorLayer.isHidden = !cursorVisible
            updateCursorLayout()
            CATransaction.commit()
        }

        private func updateCursorLayout() {
            guard let rect = videoRect(), cursorNormSize != .zero else { return }
            cursorLayer.bounds = CGRect(x: 0, y: 0,
                                        width: cursorNormSize.width * rect.width,
                                        height: cursorNormSize.height * rect.height)
            cursorLayer.position = CGPoint(x: rect.minX + cursorNorm.x * rect.width,
                                           y: rect.minY + cursorNorm.y * rect.height)
        }

        // The video is aspect-fit inside the view; map view coords into the
        // displayed video rect and normalize to [0,1].
        private func normalized(_ point: CGPoint) -> (x: Double, y: Double)? {
            guard let video = receiver?.videoSize, video != .zero,
                  bounds.width > 0, bounds.height > 0 else { return nil }
            let scale = min(bounds.width / video.width, bounds.height / video.height)
            let size = CGSize(width: video.width * scale, height: video.height * scale)
            let origin = CGPoint(x: (bounds.width - size.width) / 2,
                                 y: (bounds.height - size.height) / 2)
            let x = (point.x - origin.x) / size.width
            let y = (point.y - origin.y) / size.height
            return (min(max(x, 0), 1), min(max(y, 0), 1))
        }

        private var press = TouchPressPolicy()
        private var holdTimer: DispatchWorkItem?
        private var touchGeneration: UInt64?
        private var pencilTool: PencilTool { receiver?.selectedPencilTool ?? .pen }
        private var tapEvents = PencilGestureDeduplicator()
        private var squeezeEvents = PencilGestureDeduplicator()
        private var pencilTouch: UITouch?
        private var pencilGeneration: UInt64?
        private var lastPencil: PencilSample?
        private var hoverGeneration: UInt64?
        private var pencilHoverActive = false
        private var panGeneration: UInt64?

        private func emit(_ actions: [TouchPressPolicy.Action]) {
            for action in actions {
                receiver?.sendTouch(phase: action.phase, x: action.position.x, y: action.position.y, generation: touchGeneration)
            }
        }

        private func cancelFingerPress() {
            holdTimer?.cancel(); holdTimer = nil
            emit(press.cancel())
            touchGeneration = nil
        }

        func cancelPress() {
            cancelFingerPress()
            if let generation = pencilGeneration, let last = lastPencil {
                receiver?.sendPencil(last.cancelled, generation: generation)
            }
            if let generation = hoverGeneration ?? pencilGeneration {
                receiver?.endPencilProximity(x: lastPencil?.x ?? 0.5, y: lastPencil?.y ?? 0.5, generation: generation)
            }
            resetInput(resetGestures: false)
        }

        /// A new connection owns a new gesture epoch; old touches cannot cross it.
        func resetInput(resetGestures: Bool = true) {
            if resetGestures { tapEvents = PencilGestureDeduplicator(); squeezeEvents = PencilGestureDeduplicator() }
            holdTimer?.cancel(); holdTimer = nil
            _ = press.cancel()
            touchGeneration = nil; pencilTouch = nil; pencilGeneration = nil
            lastPencil = nil; hoverGeneration = nil; pencilHoverActive = false
            panGeneration = nil; twoFingerActive = false
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateDisplayLink()
            if window == nil { cancelPress() }
        }

        private func sendPencil(_ phase: String, touch: UITouch, event: UIEvent?) {
            if phase == "began" {
                cancelFingerPress()
                twoFingerActive = false
                panGeneration = nil
                pencilTouch = touch
                pencilGeneration = receiver?.inputGeneration
            }
            guard pencilTouch === touch, let generation = pencilGeneration else { return }
            let penPhase: PencilSample.Phase
            switch phase {
            case "began": penPhase = .down
            case "moved": penPhase = .move
            case "ended": penPhase = .up
            default: penPhase = .cancel
            }
            let samples = phase == "moved" ? Array((event?.coalescedTouches(for: touch) ?? [touch]).suffix(32)) : [touch]
            for sample in samples {
                let norm = normalized(sample.location(in: self))
                // Keep the last valid point for cancellation during a layout change.
                guard let x = norm?.x ?? lastPencil?.x, let y = norm?.y ?? lastPencil?.y else { continue }
                let pressure = sample.maximumPossibleForce > 0 ? sample.force / sample.maximumPossibleForce : 0
                let ending = penPhase == .up || penPhase == .cancel
                let roll: Double
                if #available(iOS 17.5, *) { roll = Double(sample.rollAngle).truncatingRemainder(dividingBy: 2 * .pi) } else { roll = 0 }
                guard let packet = PencilSample(phase: penPhase, x: x, y: y,
                    pressure: ending ? 0 : Double(min(1, max(0, pressure))),
                    azimuth: ending ? (lastPencil?.azimuth ?? 0) : Double(sample.azimuthAngle(in: self)),
                    altitude: ending ? (lastPencil?.altitude ?? .pi / 2) : Double(sample.altitudeAngle),
                    roll: ending ? (lastPencil?.roll ?? 0) : roll, tool: pencilTool) else { continue }
                lastPencil = packet
                receiver?.sendPencil(packet, generation: generation)
            }
            if phase == "ended" || phase == "cancelled" {
                pencilTouch = nil; pencilGeneration = nil
            }
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            performPencilGesture(preference: "pencilDoubleTapAction", system: UIPencilInteraction.preferredTapAction)
        }

        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            guard tapEvents.accept(tap.timestamp) else { return }
            performPencilGesture(preference: "pencilDoubleTapAction", system: UIPencilInteraction.preferredTapAction)
        }

        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            // UIKit also uses ended for discrete squeezes, without a preceding began.
            guard squeeze.phase == .ended, squeezeEvents.accept(squeeze.timestamp) else { return }
            performPencilGesture(preference: "pencilSqueezeAction", system: UIPencilInteraction.preferredSqueezeAction)
        }

        private func performPencilGesture(preference: String, system: UIPencilPreferredAction) {
            guard let window, window.rootViewController?.presentedViewController == nil,
                  UIApplication.shared.applicationState == .active,
                  let receiver, receiver.connected, receiver.videoSize != .zero,
                  receiver.pencilExtendedAvailable else { return }
            let selected = PencilGestureAction(rawValue: UserDefaults.standard.string(forKey: preference) ?? "system") ?? .system
            let action = selected.resolve(system: system == .switchEraser ? .toggleEraser : .none)
            guard action != .none else { return }
            if action == .toggleEraser {
                receiver.selectPencilTool(pencilTool == .pen ? .eraser : .pen)
                UIAccessibility.post(notification: .announcement, argument: pencilTool == .pen ? "画笔" : "橡皮")
            } else if let remote = PencilRemoteAction(rawValue: action.rawValue), receiver.pencilShortcutsAvailable {
                let generation = receiver.inputGeneration
                cancelPress()
                receiver.sendPencilAction(remote, generation: generation)
            }
        }

        @objc func didPencilHover(_ recognizer: UIHoverGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                guard pencilTouch == nil, let norm = normalized(recognizer.location(in: self)) else { return }
                cancelFingerPress()
                pencilHoverActive = true
                if hoverGeneration == nil { hoverGeneration = receiver?.inputGeneration }
                let roll: Double
                if #available(iOS 17.5, *) { roll = Double(recognizer.rollAngle).truncatingRemainder(dividingBy: 2 * .pi) } else { roll = 0 }
                guard let generation = hoverGeneration,
                      let sample = PencilSample(phase: .hover, x: norm.x, y: norm.y, pressure: 0,
                        azimuth: Double(recognizer.azimuthAngle(in: self)), altitude: Double(recognizer.altitudeAngle), roll: roll, tool: pencilTool) else { return }
                lastPencil = sample
                receiver?.sendPencil(sample, generation: generation)
            case .ended, .cancelled, .failed:
                if pencilTouch == nil, let generation = hoverGeneration {
                    receiver?.endPencilProximity(x: lastPencil?.x ?? 0.5, y: lastPencil?.y ?? 0.5, generation: generation)
                }
                hoverGeneration = nil; pencilHoverActive = false
            default: break
            }
        }

        private var twoFingerActive = false
        private var lastPan = CGPoint.zero
        private var lastNorm: (x: Double, y: Double) = (0.5, 0.5)

        @objc func didTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
            guard pencilTouch == nil, !pencilHoverActive,
                  let video = receiver?.videoSize, video != .zero else { return }
            switch recognizer.state {
            case .began:
                twoFingerActive = true
                lastPan = .zero
                cancelFingerPress()
                panGeneration = receiver?.inputGeneration
                // Anchor scrolling under the gesture without sending a click.
                if let n = normalized(recognizer.location(in: self)) {
                    lastNorm = n
                    receiver?.sendTouch(phase: "moved", x: n.x, y: n.y, generation: panGeneration)
                }
            case .changed:
                guard let panGeneration else { return }
                let t = recognizer.translation(in: self)
                let scale = min(bounds.width / video.width, bounds.height / video.height)
                guard scale > 0 else { return }
                // Deltas in video pixels, natural-scrolling direction.
                receiver?.sendScroll(dx: (t.x - lastPan.x) / scale,
                                     dy: (t.y - lastPan.y) / scale, generation: panGeneration)
                lastPan = t
            default:
                twoFingerActive = false
                panGeneration = nil
            }
        }

        private func send(_ phase: String, _ touches: Set<UITouch>, _ event: UIEvent?) {
            if let pencil = touches.first(where: { $0.type == .pencil }) {
                sendPencil(phase, touch: pencil, event: event)
                return
            }
            guard pencilTouch == nil, !pencilHoverActive else { return }
            if phase == "cancelled" { cancelFingerPress(); return }
            let fingers = event?.allTouches?.filter { $0.type == .direct && $0.phase != .ended && $0.phase != .cancelled }.count ?? 1
            if twoFingerActive || fingers > 1 {
                cancelFingerPress()
                return
            }
            guard let touch = touches.first(where: { $0.type == .direct }),
                  let norm = normalized(touch.location(in: self)) else { return }
            lastNorm = norm
            let position = CGPoint(x: norm.x, y: norm.y)
            switch phase {
            case "began":
                cancelFingerPress()
                touchGeneration = receiver?.inputGeneration
                press.begin(at: position, screenPoint: touch.location(in: self))
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.emit(self.press.commitHold())
                }
                holdTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + TouchPressPolicy.holdDelay, execute: work)
                return
            case "ended":
                holdTimer?.cancel(); holdTimer = nil
                emit(press.end(at: position))
                touchGeneration = nil
                return
            case "moved":
                guard touchGeneration != nil else { return }
                emit(press.move(to: touch.location(in: self)))
            default: break
            }
            if phase == "moved", let event {
                // The panel samples touches at 120Hz but UIKit delivers at
                // display refresh — forward every coalesced sample so the Mac
                // gets the full-rate drag, then UIKit's predicted touch so the
                // cursor leads toward where the finger will be (~1 frame of
                // perceived latency back; corrected by the next real sample).
                for t in (event.coalescedTouches(for: touch) ?? [touch]).suffix(32) {
                    if let n = normalized(t.location(in: self)) {
                        lastNorm = n
                        receiver?.sendTouch(phase: "moved", x: n.x, y: n.y, generation: touchGeneration)
                    }
                }
                if let predicted = event.predictedTouches(for: touch)?.last,
                   let n = normalized(predicted.location(in: self)) {
                    receiver?.sendTouch(phase: "moved", x: n.x, y: n.y, generation: touchGeneration)
                }
                return
            }
            receiver?.sendTouch(phase: phase, x: norm.x, y: norm.y, generation: touchGeneration)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { send("began", touches, event) }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { send("moved", touches, event) }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { send("ended", touches, event) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { send("cancelled", touches, event) }
    }
}
