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
        let pointerHover = UIHoverGestureRecognizer(target: view, action: #selector(VideoView.didPointerHover(_:)))
        pointerHover.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue),
            NSNumber(value: UITouch.TouchType.indirect.rawValue),
        ]
        view.addGestureRecognizer(pointerHover)
        let scrollPan = UIPanGestureRecognizer(target: view, action: #selector(VideoView.didPointerScroll(_:)))
        scrollPan.allowedTouchTypes = []
        scrollPan.allowedScrollTypesMask = .all
        view.addGestureRecognizer(scrollPan)
        let secondaryTap = UITapGestureRecognizer(target: view, action: #selector(VideoView.didSecondaryClick(_:)))
        secondaryTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        secondaryTap.buttonMaskRequired = .secondary
        secondaryTap.cancelsTouchesInView = false
        secondaryTap.delaysTouchesBegan = false
        secondaryTap.delaysTouchesEnded = false
        view.addGestureRecognizer(secondaryTap)
        let pointerInteraction = UIPointerInteraction(delegate: view)
        view.addInteraction(pointerInteraction)
        let pencil = UIPencilInteraction()
        pencil.delegate = view
        view.addInteraction(pencil)
        view.installLifecycleObservers()
        receiver.onInputReset = { [weak view] in view?.resetInput() }
        receiver.onPencilToolChange = { [weak view] in view?.cancelPress() }
        receiver.onDesktopInputRevoked = { [weak view] in view?.clearLocalDesktopInputTracking() }

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

    final class VideoView: UIView, UIPencilInteractionDelegate, UIPointerInteractionDelegate {
        let presentationID = UUID()
        weak var receiver: PhoneReceiver?
        weak var sampleBufferLayer: AVSampleBufferDisplayLayer?
        private var lifecycleObservers: [NSObjectProtocol] = []

        override var canBecomeFirstResponder: Bool { true }

        func installLifecycleObservers() {
            removeLifecycleObservers()
            let nc = NotificationCenter.default
            lifecycleObservers.append(
                nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.releaseDesktopInputIfNeeded()
                }
            )
            lifecycleObservers.append(
                nc.addObserver(forName: UIWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
                    guard let self, note.object as? UIWindow === self.window else { return }
                    self.releaseDesktopInputIfNeeded()
                }
            )
        }

        private func removeLifecycleObservers() {
            for token in lifecycleObservers {
                NotificationCenter.default.removeObserver(token)
            }
            lifecycleObservers.removeAll()
        }

        override func resignFirstResponder() -> Bool {
            releaseDesktopInputIfNeeded()
            return super.resignFirstResponder()
        }

        func retirePresentation() {
            removeLifecycleObservers()
            releaseDesktopInputIfNeeded()
            cancelPress()
            stopDisplayLink()
            metalRenderer?.onPresented = nil
            metalRenderer?.reset()
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
            let video = receiver?.videoSize ?? .zero
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let renderer = metalRenderer {
                // The metal layer scales its drawable to fill its frame, so
                // the frame itself must be the aspect-fit rect.
                renderer.updateLayout(frame: videoRect() ?? bounds, drawableSize: video)
            } else {
                // AVSBDL aspect-fits internally (videoGravity) — full bounds.
                layer.sublayers?.first?.frame = bounds
            }
            if cursorLayer.superlayer == nil { layer.addSublayer(cursorLayer) }
            updateCursorLayout()
            CATransaction.commit()
            // Rotation diagnostics — one line per layout change.
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
            cursorNorm = CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
            cursorVisible = visible
            cursorDirty = true
            if displayLink == nil { presentCursor() }
        }

        func setCursorSprite(_ image: UIImage, anchor: CGPoint, normSize: CGSize) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cursorLayer.contents = image.cgImage
            cursorLayer.anchorPoint = CGPoint(x: min(max(anchor.x, 0), 1), y: min(max(anchor.y, 0), 1))
            cursorNormSize = CGSize(width: min(max(normSize.width, 0), 1), height: min(max(normSize.height, 0), 1))
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
        private func isInsideVideoRect(_ point: CGPoint) -> Bool {
            videoRect()?.contains(point) == true
        }

        private func normalized(_ point: CGPoint) -> (x: Double, y: Double)? {
            guard let rect = videoRect(), rect.width > 0, rect.height > 0 else { return nil }
            let x = (point.x - rect.origin.x) / rect.width
            let y = (point.y - rect.origin.y) / rect.height
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
            releaseDesktopInputIfNeeded()
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
            if resetGestures {
                tapEvents = PencilGestureDeduplicator()
                squeezeEvents = PencilGestureDeduplicator()
                metalRenderer?.reset(forGeneration: receiver?.inputGeneration)
            }
            holdTimer?.cancel(); holdTimer = nil
            _ = press.cancel()
            touchGeneration = nil; pencilTouch = nil; pencilGeneration = nil
            lastPencil = nil; hoverGeneration = nil; pencilHoverActive = false
            panGeneration = nil; twoFingerActive = false
            clearLocalDesktopInputTracking()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateDisplayLink()
            if let window {
                if window.rootViewController?.presentedViewController == nil {
                    _ = becomeFirstResponder()
                }
            } else {
                releaseDesktopInputIfNeeded()
                cancelPress()
            }
        }

        private func sendPencil(_ phase: String, touch: UITouch, event: UIEvent?) {
            if phase == "began" {
                guard isInsideVideoRect(touch.location(in: self)) else { return }
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
                let point = recognizer.location(in: self)
                guard pencilTouch == nil else { return }
                guard isInsideVideoRect(point), let norm = normalized(point) else {
                    if pencilHoverActive {
                        if let generation = hoverGeneration {
                            receiver?.endPencilProximity(x: lastPencil?.x ?? 0.5, y: lastPencil?.y ?? 0.5, generation: generation)
                        }
                        hoverGeneration = nil
                        pencilHoverActive = false
                    }
                    return
                }
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
                let location = recognizer.location(in: self)
                guard isInsideVideoRect(location) else { return }
                twoFingerActive = true
                lastPan = .zero
                cancelFingerPress()
                panGeneration = receiver?.inputGeneration
                // Anchor scrolling under the gesture without sending a click.
                if let n = normalized(location) {
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
            if let pointer = touches.first(where: { $0.type == .indirectPointer || $0.type == .indirect }) {
                handleIndirectPointerTouch(phase, touch: pointer, event: event)
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
            if phase == "began", !isInsideVideoRect(touch.location(in: self)) { return }
            if phase == "began", !isFirstResponder,
               window?.rootViewController?.presentedViewController == nil {
                _ = becomeFirstResponder()
            }
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

        // MARK: - iPadOS / iOS Hardware Keyboard & Trackpad / Mouse Pointer (mac-input-v1)

        private var desktopInputGeneration: UInt64?
        private var lastPointerNorm: (x: Double, y: Double) = (0.5, 0.5)
        private var pressedMouseButtons: Set<Int> = []
        private var pointerFallbackGeneration: UInt64?
        private var lastSecondaryTouchUptime: TimeInterval = 0
        private var scrollGeneration: UInt64?
        private var lastScrollTranslation: CGPoint = .zero
        private var heldKeyCodes: Set<UInt16> = []
        private var heldModifierUsages: Set<Int> = []
        private var sentModifiers: Int = 0

        private func ensureDesktopInputGeneration(_ receiver: PhoneReceiver) -> UInt64 {
            let current = receiver.inputGeneration
            if desktopInputGeneration != current {
                clearLocalDesktopInputTracking()
                desktopInputGeneration = current
            }
            return current
        }

        func clearLocalDesktopInputTracking() {
            desktopInputGeneration = nil
            pressedMouseButtons.removeAll()
            pointerFallbackGeneration = nil
            scrollGeneration = nil
            lastScrollTranslation = .zero
            heldKeyCodes.removeAll()
            heldModifierUsages.removeAll()
            sentModifiers = 0
        }

        func releaseDesktopInputIfNeeded() {
            let hadHeldState = !pressedMouseButtons.isEmpty
                || !heldKeyCodes.isEmpty
                || !heldModifierUsages.isEmpty
                || sentModifiers != 0
            let gen = desktopInputGeneration ?? receiver?.inputGeneration
            clearLocalDesktopInputTracking()
            if hadHeldState, let gen, let receiver, receiver.desktopInputAvailable {
                receiver.releaseDesktopInput(generation: gen)
            }
        }

        func pointerInteraction(
            _ interaction: UIPointerInteraction,
            regionFor request: UIPointerRegionRequest,
            defaultRegion: UIPointerRegion
        ) -> UIPointerRegion? {
            guard receiver?.connected == true,
                  let rect = videoRect(),
                  rect.contains(request.location) else { return nil }
            return UIPointerRegion(rect: rect, identifier: "displayweave.video" as NSString)
        }

        func pointerInteraction(
            _ interaction: UIPointerInteraction,
            styleFor region: UIPointerRegion
        ) -> UIPointerStyle? {
            if cursorVisible && cursorLayer.contents != nil {
                return UIPointerStyle.hidden()
            }
            return nil
        }

        @objc func didPointerHover(_ recognizer: UIHoverGestureRecognizer) {
            guard pencilTouch == nil, !pencilHoverActive,
                  let receiver, receiver.connected, receiver.videoSize != .zero else { return }
            switch recognizer.state {
            case .began, .changed:
                let point = recognizer.location(in: self)
                guard isInsideVideoRect(point), let norm = normalized(point) else { return }
                lastNorm = norm
                lastPointerNorm = norm
                if receiver.desktopInputAvailable {
                    let gen = ensureDesktopInputGeneration(receiver)
                    syncModifiers(from: recognizer.modifierFlags, generation: gen)
                    receiver.sendDesktopInput(
                        OutgoingDesktopInput(kind: .move, modifiers: sentModifiers, x: norm.x, y: norm.y),
                        generation: gen
                    )
                } else {
                    receiver.sendTouch(phase: "moved", x: norm.x, y: norm.y, generation: receiver.inputGeneration)
                }
            default:
                break
            }
        }

        @objc func didPointerScroll(_ recognizer: UIPanGestureRecognizer) {
            guard pencilTouch == nil, !pencilHoverActive,
                  let receiver, receiver.connected,
                  receiver.videoSize != .zero else { return }
            switch recognizer.state {
            case .began:
                let loc = recognizer.location(in: self)
                guard isInsideVideoRect(loc), let norm = normalized(loc) else {
                    scrollGeneration = nil
                    return
                }
                scrollGeneration = receiver.inputGeneration
                lastScrollTranslation = .zero
                lastPointerNorm = norm
            case .changed:
                guard let gen = scrollGeneration else { return }
                let video = receiver.videoSize
                let scale = min(bounds.width / video.width, bounds.height / video.height)
                guard scale > 0 else { return }
                let t = recognizer.translation(in: self)
                let dx = min(4096.0, max(-4096.0, Double((t.x - lastScrollTranslation.x) / scale)))
                let dy = min(4096.0, max(-4096.0, Double((t.y - lastScrollTranslation.y) / scale)))
                lastScrollTranslation = t
                guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return }
                let loc = recognizer.location(in: self)
                if isInsideVideoRect(loc), let norm = normalized(loc) {
                    lastPointerNorm = norm
                }
                if receiver.desktopInputAvailable {
                    let activeGen = ensureDesktopInputGeneration(receiver)
                    syncModifiers(from: recognizer.modifierFlags, generation: activeGen)
                    receiver.sendDesktopInput(
                        OutgoingDesktopInput(
                            kind: .scroll,
                            modifiers: sentModifiers,
                            x: lastPointerNorm.x,
                            y: lastPointerNorm.y,
                            dx: dx,
                            dy: dy
                        ),
                        generation: activeGen
                    )
                } else {
                    receiver.sendScroll(dx: dx, dy: dy, generation: gen)
                }
            default:
                scrollGeneration = nil
            }
        }

        @objc func didSecondaryClick(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let receiver, receiver.connected, receiver.desktopInputAvailable else { return }
            guard ProcessInfo.processInfo.systemUptime - lastSecondaryTouchUptime > 0.12 else { return }
            let point = recognizer.location(in: self)
            guard isInsideVideoRect(point), let norm = normalized(point) else { return }
            if !isFirstResponder, window?.rootViewController?.presentedViewController == nil {
                _ = becomeFirstResponder()
            }
            let gen = ensureDesktopInputGeneration(receiver)
            syncModifiers(from: recognizer.modifierFlags, generation: gen)
            lastPointerNorm = norm
            receiver.sendDesktopInput(
                OutgoingDesktopInput(kind: .buttonDown, modifiers: sentModifiers, x: norm.x, y: norm.y, button: 1, clicks: 1),
                generation: gen
            )
            receiver.sendDesktopInput(
                OutgoingDesktopInput(kind: .buttonUp, modifiers: sentModifiers, x: norm.x, y: norm.y, button: 1, clicks: 1),
                generation: gen
            )
        }

        private static func buttonsFromMask(_ mask: UIEvent.ButtonMask) -> Set<Int> {
            var set = Set<Int>()
            if mask.contains(.primary) { set.insert(0) }
            if mask.contains(.secondary) { set.insert(1) }
            if (mask.rawValue & (1 << 2)) != 0 { set.insert(2) }
            return set
        }

        private func handleIndirectPointerTouch(_ phase: String, touch: UITouch, event: UIEvent?) {
            guard pencilTouch == nil, !pencilHoverActive,
                  let receiver, receiver.connected, receiver.videoSize != .zero else { return }
            let loc = touch.location(in: self)
            guard let norm = normalized(loc) else { return }

            if receiver.desktopInputAvailable {
                let gen = ensureDesktopInputGeneration(receiver)
                syncModifiers(from: event?.modifierFlags ?? [], generation: gen)
                let clicks = min(3, max(1, touch.tapCount))

                switch phase {
                case "began":
                    guard isInsideVideoRect(loc) else { return }
                    if !isFirstResponder, window?.rootViewController?.presentedViewController == nil {
                        _ = becomeFirstResponder()
                    }
                    lastPointerNorm = norm
                    lastNorm = norm
                    var buttons = Self.buttonsFromMask(event?.buttonMask ?? [])
                    if buttons.isEmpty { buttons.insert(0) }
                    if buttons.contains(1) {
                        lastSecondaryTouchUptime = ProcessInfo.processInfo.systemUptime
                    }
                    for btn in buttons.sorted() where !pressedMouseButtons.contains(btn) {
                        pressedMouseButtons.insert(btn)
                        receiver.sendDesktopInput(
                            OutgoingDesktopInput(
                                kind: .buttonDown,
                                modifiers: sentModifiers,
                                x: norm.x,
                                y: norm.y,
                                button: btn,
                                clicks: clicks
                            ),
                            generation: gen
                        )
                    }
                case "moved":
                    guard !pressedMouseButtons.isEmpty || isInsideVideoRect(loc) else { return }
                    let samples = Array((event?.coalescedTouches(for: touch) ?? [touch]).suffix(8))
                    for sample in samples {
                        guard let sampleNorm = normalized(sample.location(in: self)) else { continue }
                        lastPointerNorm = sampleNorm
                        lastNorm = sampleNorm
                        receiver.sendDesktopInput(
                            OutgoingDesktopInput(
                                kind: .move,
                                modifiers: sentModifiers,
                                x: sampleNorm.x,
                                y: sampleNorm.y
                            ),
                            generation: gen
                        )
                    }
                case "ended":
                    lastPointerNorm = norm
                    lastNorm = norm
                    let otherActive = (event?.allTouches ?? []).contains {
                        ($0.type == .indirectPointer || $0.type == .indirect)
                            && $0 !== touch
                            && $0.phase != .ended
                            && $0.phase != .cancelled
                    }
                    let remaining = otherActive ? Self.buttonsFromMask(event?.buttonMask ?? []) : []
                    let released = pressedMouseButtons.subtracting(remaining).sorted()
                    for btn in released {
                        pressedMouseButtons.remove(btn)
                        receiver.sendDesktopInput(
                            OutgoingDesktopInput(
                                kind: .buttonUp,
                                modifiers: sentModifiers,
                                x: norm.x,
                                y: norm.y,
                                button: btn,
                                clicks: clicks
                            ),
                            generation: gen
                        )
                    }
                default:
                    let released = pressedMouseButtons.sorted()
                    pressedMouseButtons.removeAll()
                    for btn in released {
                        receiver.sendDesktopInput(
                            OutgoingDesktopInput(
                                kind: .buttonUp,
                                modifiers: sentModifiers,
                                x: norm.x,
                                y: norm.y,
                                button: btn,
                                clicks: 1
                            ),
                            generation: gen
                        )
                    }
                }
            } else {
                // Legacy unencrypted fallback: primary pointer button maps to direct touch.
                switch phase {
                case "began":
                    guard isInsideVideoRect(loc) else { return }
                    let buttons = Self.buttonsFromMask(event?.buttonMask ?? [])
                    guard buttons.isEmpty || buttons.contains(0) else { return }
                    pointerFallbackGeneration = receiver.inputGeneration
                    lastNorm = norm
                    receiver.sendTouch(phase: "began", x: norm.x, y: norm.y, generation: pointerFallbackGeneration)
                case "moved":
                    guard let gen = pointerFallbackGeneration else { return }
                    lastNorm = norm
                    receiver.sendTouch(phase: "moved", x: norm.x, y: norm.y, generation: gen)
                case "ended":
                    guard let gen = pointerFallbackGeneration else { return }
                    pointerFallbackGeneration = nil
                    lastNorm = norm
                    receiver.sendTouch(phase: "ended", x: norm.x, y: norm.y, generation: gen)
                default:
                    pointerFallbackGeneration = nil
                }
            }
        }

        private func syncModifiers(from flags: UIKeyModifierFlags, generation: UInt64) {
            var mask = Self.macModifierMask(from: flags)
            for usage in heldModifierUsages {
                mask |= Self.modifierBit(forHIDUsage: usage)
            }
            mask &= 0x1F
            guard mask != sentModifiers else { return }
            sentModifiers = mask
            receiver?.sendDesktopInput(
                OutgoingDesktopInput(kind: .modifiers, modifiers: mask),
                generation: generation
            )
        }

        private static func macModifierMask(from flags: UIKeyModifierFlags) -> Int {
            var bits = 0
            if flags.contains(.shift) { bits |= (1 << 0) }
            if flags.contains(.control) { bits |= (1 << 1) }
            if flags.contains(.alternate) { bits |= (1 << 2) }
            if flags.contains(.command) { bits |= (1 << 3) }
            if flags.contains(.alphaShift) { bits |= (1 << 4) }
            return bits
        }

        private static func modifierBit(forHIDUsage usage: Int) -> Int {
            switch usage {
            case 0xE1, 0xE5: return 1 << 0 // Left / Right Shift
            case 0xE0, 0xE4: return 1 << 1 // Left / Right Control
            case 0xE2, 0xE6: return 1 << 2 // Left / Right Option (Alt)
            case 0xE3, 0xE7: return 1 << 3 // Left / Right Command (GUI)
            default: return 0
            }
        }

        private static func isModifierHIDUsage(_ usage: Int) -> Bool {
            usage == 0x39 || (0xE0...0xE7).contains(usage)
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard window?.rootViewController?.presentedViewController == nil,
                  UIApplication.shared.applicationState == .active,
                  let receiver, receiver.connected, receiver.desktopInputAvailable else {
                super.pressesBegan(presses, with: event)
                return
            }
            let gen = ensureDesktopInputGeneration(receiver)
            let flags = event?.modifierFlags ?? []
            var unhandled = Set<UIPress>()

            for press in presses {
                guard let key = press.key else {
                    unhandled.insert(press)
                    continue
                }
                let usage = Int(key.keyCode.rawValue)
                // Local escape hatch matching Mac receiver: Control + Option + Escape releases capture.
                if usage == 0x29, flags.contains(.control), flags.contains(.alternate) {
                    releaseDesktopInputIfNeeded()
                    _ = resignFirstResponder()
                    return
                }
                if Self.isModifierHIDUsage(usage) {
                    if usage != 0x39 {
                        heldModifierUsages.insert(usage)
                    }
                    syncModifiers(from: flags.union(key.modifierFlags), generation: gen)
                    continue
                }
                syncModifiers(from: flags, generation: gen)
                guard let macCode = Self.hidUsageToMacKeyCode(usage) else {
                    unhandled.insert(press)
                    continue
                }
                let isRepeat = heldKeyCodes.contains(macCode)
                if !isRepeat {
                    // DesktopInputInjector caps simultaneous held keys at 16.
                    guard heldKeyCodes.count < 15 else { continue }
                    heldKeyCodes.insert(macCode)
                }
                receiver.sendDesktopInput(
                    OutgoingDesktopInput(
                        kind: .keyDown,
                        modifiers: sentModifiers,
                        keyCode: macCode,
                        repeating: isRepeat
                    ),
                    generation: gen
                )
            }
            if !unhandled.isEmpty {
                super.pressesBegan(unhandled, with: event)
            }
        }

        override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let receiver, receiver.connected, receiver.desktopInputAvailable else {
                super.pressesChanged(presses, with: event)
                return
            }
            let gen = ensureDesktopInputGeneration(receiver)
            syncModifiers(from: event?.modifierFlags ?? [], generation: gen)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let receiver, receiver.connected, receiver.desktopInputAvailable else {
                super.pressesEnded(presses, with: event)
                return
            }
            let gen = ensureDesktopInputGeneration(receiver)
            let flags = event?.modifierFlags ?? []
            var unhandled = Set<UIPress>()

            for press in presses {
                guard let key = press.key else {
                    unhandled.insert(press)
                    continue
                }
                let usage = Int(key.keyCode.rawValue)
                if Self.isModifierHIDUsage(usage) {
                    heldModifierUsages.remove(usage)
                    syncModifiers(from: flags, generation: gen)
                    continue
                }
                syncModifiers(from: flags, generation: gen)
                guard let macCode = Self.hidUsageToMacKeyCode(usage) else {
                    unhandled.insert(press)
                    continue
                }
                if heldKeyCodes.remove(macCode) != nil {
                    receiver.sendDesktopInput(
                        OutgoingDesktopInput(
                            kind: .keyUp,
                            modifiers: sentModifiers,
                            keyCode: macCode,
                            repeating: false
                        ),
                        generation: gen
                    )
                }
            }
            if !unhandled.isEmpty {
                super.pressesEnded(unhandled, with: event)
            }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            releaseDesktopInputIfNeeded()
            super.pressesCancelled(presses, with: event)
        }

        /// Maps USB HID Usage Page 0x07 key codes (`UIKeyboardHIDUsage.rawValue`)
        /// to macOS virtual key codes (`CGKeyCode` / Carbon `kVK_*`, `0...126`).
        private static func hidUsageToMacKeyCode(_ usage: Int) -> UInt16? {
            switch usage {
            // Letters A-Z
            case 0x04: return 0    // A
            case 0x05: return 11   // B
            case 0x06: return 8    // C
            case 0x07: return 2    // D
            case 0x08: return 14   // E
            case 0x09: return 3    // F
            case 0x0A: return 5    // G
            case 0x0B: return 4    // H
            case 0x0C: return 34   // I
            case 0x0D: return 38   // J
            case 0x0E: return 40   // K
            case 0x0F: return 37   // L
            case 0x10: return 46   // M
            case 0x11: return 45   // N
            case 0x12: return 31   // O
            case 0x13: return 35   // P
            case 0x14: return 12   // Q
            case 0x15: return 15   // R
            case 0x16: return 1    // S
            case 0x17: return 17   // T
            case 0x18: return 32   // U
            case 0x19: return 9    // V
            case 0x1A: return 13   // W
            case 0x1B: return 7    // X
            case 0x1C: return 16   // Y
            case 0x1D: return 6    // Z
            // Number row 1-0
            case 0x1E: return 18   // 1
            case 0x1F: return 19   // 2
            case 0x20: return 20   // 3
            case 0x21: return 21   // 4
            case 0x22: return 23   // 5
            case 0x23: return 22   // 6
            case 0x24: return 26   // 7
            case 0x25: return 28   // 8
            case 0x26: return 25   // 9
            case 0x27: return 29   // 0
            // Controls & punctuation
            case 0x28: return 36   // Return
            case 0x29: return 53   // Escape
            case 0x2A: return 51   // Delete (Backspace)
            case 0x2B: return 48   // Tab
            case 0x2C: return 49   // Space
            case 0x2D: return 27   // -
            case 0x2E: return 24   // =
            case 0x2F: return 33   // [
            case 0x30: return 30   // ]
            case 0x31, 0x32: return 42 // \
            case 0x33: return 41   // ;
            case 0x34: return 39   // '
            case 0x35: return 50   // `
            case 0x36: return 43   // ,
            case 0x37: return 47   // .
            case 0x38: return 44   // /
            case 0x64: return 10   // ISO Section / Non-US \
            // Function keys F1-F20
            case 0x3A: return 122  // F1
            case 0x3B: return 120  // F2
            case 0x3C: return 99   // F3
            case 0x3D: return 118  // F4
            case 0x3E: return 96   // F5
            case 0x3F: return 97   // F6
            case 0x40: return 98   // F7
            case 0x41: return 100  // F8
            case 0x42: return 101  // F9
            case 0x43: return 109  // F10
            case 0x44: return 103  // F11
            case 0x45: return 111  // F12
            case 0x68: return 105  // F13
            case 0x69: return 107  // F14
            case 0x6A: return 113  // F15
            case 0x6B: return 106  // F16
            case 0x6C: return 64   // F17
            case 0x6D: return 79   // F18
            case 0x6E: return 80   // F19
            case 0x6F: return 90   // F20
            // Navigation & Arrows
            case 0x49: return 114  // Insert / Help
            case 0x4A: return 115  // Home
            case 0x4B: return 116  // PageUp
            case 0x4C: return 117  // ForwardDelete
            case 0x4D: return 119  // End
            case 0x4E: return 121  // PageDown
            case 0x4F: return 124  // RightArrow
            case 0x50: return 123  // LeftArrow
            case 0x51: return 125  // DownArrow
            case 0x52: return 126  // UpArrow
            // Keypad
            case 0x53: return 71   // Keypad Clear / NumLock
            case 0x54: return 75   // Keypad /
            case 0x55: return 67   // Keypad *
            case 0x56: return 78   // Keypad -
            case 0x57: return 69   // Keypad +
            case 0x58: return 76   // Keypad Enter
            case 0x59: return 83   // Keypad 1
            case 0x5A: return 84   // Keypad 2
            case 0x5B: return 85   // Keypad 3
            case 0x5C: return 86   // Keypad 4
            case 0x5D: return 87   // Keypad 5
            case 0x5E: return 88   // Keypad 6
            case 0x5F: return 89   // Keypad 7
            case 0x60: return 91   // Keypad 8
            case 0x61: return 92   // Keypad 9
            case 0x62: return 82   // Keypad 0
            case 0x63: return 65   // Keypad .
            case 0x67: return 81   // Keypad =
            // JIS keys
            case 0x87: return 94   // JIS Underscore
            case 0x89: return 93   // JIS Yen
            case 0x90: return 104  // JIS Kana
            case 0x91: return 102  // JIS Eisu
            default: return nil
            }
        }
    }
}
