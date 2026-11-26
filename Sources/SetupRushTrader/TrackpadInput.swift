import SwiftUI
import AppKit

enum ArmDirection { case long, short }

// Spec §7.1.4 / CH-25a: trackpad two-finger horizontal = pan time axis, pinch = zoom,
// two-finger vertical swipe = arm long/short (now a joystick-style pull gesture — see
// ContentView.GestureArmOverlay). Mouse equivalents (scroll wheel, ⌥+scroll, B/S keys)
// are wired in ContentView, not here — this view only owns trackpad gestures that have
// no SwiftUI gesture modifier equivalent on macOS.
final class TrackpadCaptureNSView: NSView {
    var onPanX: (CGFloat) -> Void = { _ in }
    var onZoom: (CGFloat, CGFloat) -> Void = { _, _ in } // (magnification, anchor x in view points)
    var onGestureBegin: () -> Void = {}
    var onGestureChange: (CGFloat) -> Void = { _ in }
    var onGestureEnd: (CGFloat) -> Void = { _ in }

    private var verticalAccum: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        // Spec §7.1.4: "⌥ (Option) + scroll, anchored at cursor" — the mouse equivalent of
        // pinch-zoom. Also a second, simpler path to actually trigger zoom at all, since a
        // trackpad's magnify() gesture has been unreliable to verify in this environment.
        if event.modifierFlags.contains(.option) {
            let anchorX = convert(event.locationInWindow, from: nil).x
            onZoom(event.scrollingDeltaY / 200, anchorX)
            return
        }
        if event.phase.contains(.began) {
            verticalAccum = 0
            onGestureBegin()
        }
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            onPanX(event.scrollingDeltaX)
        } else {
            // ponytail: sign depends on "natural scrolling" setting; recalibrate against
            // real hardware once available — negative accum reads as pulled up (long).
            verticalAccum += event.scrollingDeltaY
            onGestureChange(verticalAccum)
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            onGestureEnd(verticalAccum)
            verticalAccum = 0
        }
    }

    override func magnify(with event: NSEvent) {
        // CH-25: "pinch, anchored at pinch centre" — pass the pointer location so the
        // candle under your fingers stays put instead of the view zooming from its left edge.
        let anchorX = convert(event.locationInWindow, from: nil).x
        onZoom(event.magnification, anchorX)
    }
}

struct TrackpadCapture: NSViewRepresentable {
    var onPanX: (CGFloat) -> Void
    var onZoom: (CGFloat, CGFloat) -> Void
    var onGestureBegin: () -> Void
    var onGestureChange: (CGFloat) -> Void
    var onGestureEnd: (CGFloat) -> Void

    func makeNSView(context: Context) -> TrackpadCaptureNSView {
        let v = TrackpadCaptureNSView()
        updateNSView(v, context: context)
        return v
    }

    func updateNSView(_ view: TrackpadCaptureNSView, context: Context) {
        view.onPanX = onPanX
        view.onZoom = onZoom
        view.onGestureBegin = onGestureBegin
        view.onGestureChange = onGestureChange
        view.onGestureEnd = onGestureEnd
    }
}
