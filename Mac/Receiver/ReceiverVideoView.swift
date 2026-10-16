// Adapted from peetzweg/opendisplay MacReceiver/MacReceiver.swift (GPL-3.0).
// Source: b9eec1f232fb5ea571c87e8392379a84f47b237f.
import AppKit
import AVFoundation
import Combine

@MainActor
final class ReceiverVideoView: NSView {
    private weak var receiver: StreamReceiver?
    private let displayLayer: AVSampleBufferDisplayLayer
    private var videoSizeObserver: AnyCancellable?
    private var inputCapture: ReceiverDesktopInputCapture?

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

    init(receiver: StreamReceiver) {
        self.receiver = receiver
        self.displayLayer = receiver.displayLayer
        super.init(frame: .zero)
        inputCapture = ReceiverDesktopInputCapture(view: self, receiver: receiver)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // AVSBDL aspect-fits internally (videoGravity) — give it full bounds.
        displayLayer.frame = bounds
        layer?.addSublayer(displayLayer)
        layer?.addSublayer(cursorLayer)

        receiver.onReset = { [weak self] in
            self?.cursorLayer.contents = nil
            self?.cursorLayer.isHidden = true
            self?.cursorVisible = false
        }
        receiver.onCursor = { [weak self] x, y, visible in
            self?.moveCursor(x: x, y: y, visible: visible)
        }
        receiver.onCursorImage = { [weak self] image, anchor, normSize in
            self?.setCursorSprite(image, anchor: anchor, normSize: normSize)
        }
        // videoSize arrives after the format description — re-fit the layers.
        videoSizeObserver = receiver.$videoSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsLayout = true }


    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool {
        inputCapture?.release()
        return super.resignFirstResponder()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        inputCapture?.detach()
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        inputCapture?.attach()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: blankCursor)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        updateCursorLayout()
        CATransaction.commit()
    }

    /// Aspect-fit rect of the video inside the view (same math as iOS).
    private func videoRect() -> CGRect? {
        guard let video = receiver?.videoSize, video != .zero,
              bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(bounds.width / video.width, bounds.height / video.height)
        let size = CGSize(width: video.width * scale, height: video.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2,
                      y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func moveCursor(x: Double, y: Double, visible: Bool) {
        cursorNorm = CGPoint(x: x, y: y)
        cursorVisible = visible
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.isHidden = !visible || cursorLayer.contents == nil
        updateCursorLayout()
        CATransaction.commit()
    }

    private func setCursorSprite(_ image: CGImage, anchor: CGPoint, normSize: CGSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.contents = image
        // The wire anchor is the hotspot from the image's TOP-left; AppKit
        // layer unit coords run bottom-up — flip y once here.
        cursorLayer.anchorPoint = CGPoint(x: anchor.x, y: 1 - anchor.y)
        cursorNormSize = normSize
        cursorLayer.isHidden = !cursorVisible
        updateCursorLayout()
        CATransaction.commit()
    }

    private func updateCursorLayout() {
        guard let rect = videoRect(), cursorNormSize != .zero else { cursorLayer.isHidden = true; return }
        cursorLayer.isHidden = !cursorVisible || cursorLayer.contents == nil
        cursorLayer.bounds = CGRect(x: 0, y: 0,
                                    width: cursorNormSize.width * rect.width,
                                    height: cursorNormSize.height * rect.height)
        // Video-space y grows downward, view coords grow upward — flip.
        cursorLayer.position = CGPoint(x: rect.minX + cursorNorm.x * rect.width,
                                       y: rect.maxY - cursorNorm.y * rect.height)
    }
}

// MARK: - Performance overlay host

// This Mac's own pointer over the video reads as a second, dead cursor on
// what acts as a monitor — blank it there. The streamed sender cursor
// (cursorLayer) is the pointer that matters. File-scope so both the video
// view and the overlay above it use the same cursor.
private let blankCursor: NSCursor = {
    let size = NSSize(width: 1, height: 1)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.clear.set()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return NSCursor(image: image, hotSpot: .zero)
}()
