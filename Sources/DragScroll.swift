import Cocoa

/// Posts scroll events with Mac Mouse Fix's exact field layout (see its GestureScrollSimulator):
/// the point deltas carry the pixels, the line deltas are pixels/10 run through a sub-pixelator so
/// most frames carry zero lines, and the fixed-point fields mirror those line deltas.
///
/// Letting `CGEvent(scrollWheelEvent2Source:units:.pixel…)` fill these in instead rounds every frame
/// up to a whole line, so an app that scrolls by line delta (many of them do) travels several times
/// too far over a long momentum tail.
final class ScrollPoster {
    private var lineCarry = (x: 0.0, y: 0.0)

    /// Begins a new sub-pixel accumulation. Mac Mouse Fix resets its pixelator when a gesture begins
    /// and again when a momentum animation starts.
    func resetLines() { lineCarry = (0, 0) }

    func post(dx: Double, dy: Double,
              phase: GestureEngine.ScrollPhase?,
              momentum: GestureEngine.MomentumPhase = .none,
              flags: CGEventFlags = []) {
        if HotKeyPoster.dryRun {
            Log.info("DRYRUN scroll dx=\(dx) dy=\(dy) phase=\(phase.map { "\($0)" } ?? "-") momentum=\(momentum)")
            return
        }
        guard let e = CGEvent(source: nil) else { return }
        e.type = .scrollWheel
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)

        // Whole lines, carrying the fraction between frames.
        let fx = dx / 10 + lineCarry.x, fy = dy / 10 + lineCarry.y
        let lx = fx.rounded(.towardZero), ly = fy.rounded(.towardZero)
        lineCarry = (fx - lx, fy - ly)

        e.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(ly))
        e.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(lx))
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
        e.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Int64(ly) << 16)
        e.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Int64(lx) << 16)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase?.rawValue ?? 0)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum.rawValue)
        e.setIntegerValueField(.eventSourceUserData, value: HotKeyPoster.eventTag)
        e.flags = flags
        if let cursor = CGEvent(source: nil)?.location { e.location = cursor }
        e.post(tap: .cgSessionEventTap)
    }
}

/// Drag-to-scroll ("Scroll & Navigate"), modelled on Mac Mouse Fix's twoFingerSwipe drag output.
///
/// Pointer movement is never posted directly. Each mouse report adds to the distance still to travel
/// and restarts a 50 ms linear animation (Mac Mouse Fix uses 3/60 s), so the content moves at the
/// speed of the drag but a few frames behind it.
///
/// On release the remaining distance is **not** flushed: the animation keeps draining at the same
/// speed for what is left of those 50 ms, and momentum then starts from exactly the speed the
/// content was already moving at. Flushing the remainder in one frame, or launching momentum from
/// the raw pointer speed instead of the animated speed, are what made releases "kick".
final class DragScrollAnimator {
    private let smoothingDuration = 3.0 / 60.0     // Mac Mouse Fix's smoothing animator duration
    private let frameInterval = 1.0 / 120.0
    // Mac Mouse Fix's momentum drag curve: v' = -30 · v^0.7, stopping at 1 px/s.
    private let dragCoefficient = 30.0
    private let dragExponent = 0.7
    private let stopSpeed = 1.0
    /// Mac Mouse Fix drops momentum when the pointer had already stopped before the button came up.
    private let mouseMovingMaxInterval = 0.1

    private let poster = ScrollPoster()
    /// Mac Mouse Fix drives its animator from a display link off the main thread. Ours runs on its own
    /// high-priority queue for the same reason: a 1000 Hz mouse floods the main run loop with event-tap
    /// callbacks, and a frame that lands late would otherwise emit the whole remaining distance at once.
    private let queue = DispatchQueue(label: "com.wateruse.MouseDragFix.dragscroll", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var lastFrame: CFTimeInterval = 0

    private var left = (x: 0.0, y: 0.0)       // px still to travel
    private var speed = (x: 0.0, y: 0.0)      // px/s the content is moving at
    private var carry = (x: 0.0, y: 0.0)      // sub-pixel remainder
    private var lastEmitTime: CFTimeInterval = 0

    private var began = false
    private var endPending = false
    private var wantMomentum = false
    private var inMomentum = false
    private var momentumFirstFrame = true

    // MARK: Drag

    func begin() {
        queue.async { [self] in
            cancelOnQueue()
            poster.resetLines()
            left = (0, 0); speed = (0, 0); carry = (0, 0)
            began = false; endPending = false; inMomentum = false
            lastEmitTime = CACurrentMediaTime()
            lastFrame = lastEmitTime
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + frameInterval, repeating: frameInterval, leeway: .milliseconds(1))
            t.setEventHandler { [weak self] in self?.frame() }
            t.resume()
            timer = t
        }
    }

    /// One mouse report's worth of movement.
    func input(dx: Double, dy: Double) {
        queue.async { [self] in
            left.x += dx; left.y += dy
            // Linear restart: whatever is left is spread evenly over a fresh smoothing window.
            speed = (left.x / smoothingDuration, left.y / smoothingDuration)
        }
    }

    /// Button released. The animation drains first; momentum starts when it runs out.
    func end(momentum: Bool) {
        queue.async { [self] in
            guard timer != nil, !inMomentum else { return }
            wantMomentum = momentum
            endPending = true
            if left.x == 0, left.y == 0 { finishDrag() }
        }
    }

    /// Stops everything without momentum (app disabled, tap lost, a new gesture starting).
    func cancel() { queue.async { [self] in cancelOnQueue() } }

    private func cancelOnQueue() {
        if inMomentum {
            inMomentum = false
            poster.post(dx: 0, dy: 0, phase: nil, momentum: .end)
        } else if began {
            poster.post(dx: 0, dy: 0, phase: .ended)
        }
        began = false; endPending = false
        left = (0, 0); speed = (0, 0); carry = (0, 0)
        timer?.cancel(); timer = nil
    }

    // MARK: Frames

    private func frame() {
        let now = CACurrentMediaTime()
        let dt = min(2 * frameInterval, max(0.001, now - lastFrame))
        lastFrame = now

        if inMomentum { momentumFrame(dt: dt); return }

        guard left.x != 0 || left.y != 0 else {
            if endPending { finishDrag() }
            return
        }
        var ex = speed.x * dt, ey = speed.y * dt
        if abs(ex) >= abs(left.x) { ex = left.x }
        if abs(ey) >= abs(left.y) { ey = left.y }
        left.x -= ex; left.y -= ey

        let fx = ex + carry.x, fy = ey + carry.y
        let ix = fx.rounded(.towardZero), iy = fy.rounded(.towardZero)
        carry = (fx - ix, fy - iy)
        if ix != 0 || iy != 0 || !began {
            poster.post(dx: ix, dy: iy, phase: began ? .changed : .began)
            began = true
        }
        lastEmitTime = now

        if left.x == 0, left.y == 0, endPending { finishDrag() }
    }

    private func finishDrag() {
        endPending = false
        poster.post(dx: 0, dy: 0, phase: .ended)   // zero-delta ended event, as Mac Mouse Fix posts it
        began = false

        // Exit velocity = the speed the content was animating at. Mac Mouse Fix expresses the same
        // thing as "last delta / time since it was sent"; taking the animated speed directly avoids
        // the final partial frame of the drain (which is a sliver, not a frame's worth) reading as a
        // near-stop. The interval still scales it down the same way if the animation went idle first.
        let now = CACurrentMediaTime()
        let interval = max(frameInterval, now - lastEmitTime)
        let decay = frameInterval / interval
        let vx = speed.x * decay, vy = speed.y * decay

        Log.debug("drag-scroll release: \(Int(hypot(vx, vy))) px/s, idle \(Int((now - lastEmitTime) * 1000)) ms")
        guard wantMomentum,
              now - lastEmitTime <= mouseMovingMaxInterval,
              hypot(vx, vy) > stopSpeed else {
            timer?.cancel(); timer = nil
            return
        }
        speed = (vx, vy)
        carry = (0, 0)
        poster.resetLines()
        inMomentum = true
        momentumFirstFrame = true
    }

    private func momentumFrame(dt: Double) {
        let v = hypot(speed.x, speed.y)
        let nv = max(0, v - dragCoefficient * pow(v, dragExponent) * dt)
        guard nv > stopSpeed else {
            inMomentum = false
            poster.post(dx: 0, dy: 0, phase: nil, momentum: .end)
            timer?.cancel(); timer = nil
            return
        }
        speed = (speed.x * nv / v, speed.y * nv / v)
        let fx = speed.x * dt + carry.x, fy = speed.y * dt + carry.y
        let ix = fx.rounded(.towardZero), iy = fy.rounded(.towardZero)
        carry = (fx - ix, fy - iy)
        poster.post(dx: ix, dy: iy, phase: nil, momentum: momentumFirstFrame ? .begin : .continue)
        momentumFirstFrame = false
    }
}
