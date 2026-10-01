import XCTest

final class AnnotatorZoomTests: XCTestCase {
    typealias Effect = AnnotatorZoom.Effect

    /// A 400x300 frame in a room with 30 points above it and 110 below, so the height fills first:
    /// each side reaches the room at its own level, 2.5 across and 1.47 down.
    private let fitted = CGRect(x: 300, y: 250, width: 400, height: 300)
    private let room = CGRect(x: 0, y: 140, width: 1000, height: 440)
    private let edge = AnnotatorZoom.EdgePull(band: 120, pull: 0.5)

    /// An image opened in `fitted` whose flight has landed.
    private func landed() -> AnnotatorZoom {
        var zoom = AnnotatorZoom()
        zoom.edge = edge
        XCTAssertNil(zoom.reduce(.prepare(fitted: fitted, room: room)))
        _ = zoom.reduce(.tick(1))
        XCTAssertNil(zoom.reduce(.landed))
        return zoom
    }

    /// Carries the level to the spring's target, as the tween does, and answers every spring the
    /// arrival asks for in turn.
    private func settle(_ zoom: inout AnnotatorZoom, _ effect: Effect?) {
        var next = effect
        while case .spring(let level, _)? = next {
            _ = zoom.reduce(.tick(level))
            next = zoom.reduce(.arrived)
        }
    }

    private func target(_ effect: Effect?) -> CGFloat? {
        if case .spring(let level, _)? = effect { return level }
        return nil
    }

    private func seconds(_ effect: Effect?) -> Double? {
        if case .spring(_, let seconds)? = effect { return seconds }
        return nil
    }

    private func assertEqual(_ a: CGRect, _ b: CGRect, _ message: String = "", line: UInt = #line) {
        for (x, y) in [(a.minX, b.minX), (a.minY, b.minY), (a.width, b.width), (a.height, b.height)] {
            XCTAssertEqual(x, y, accuracy: 1e-6, "\(a) is not \(b) \(message)", line: line)
        }
    }

    func testNothingZoomsBeforeTheFlightLands() {
        var zoom = AnnotatorZoom()
        _ = zoom.reduce(.prepare(fitted: fitted, room: room))
        let inputs: [AnnotatorZoom.Input] = [
            .zoomIn, .fit, .smart(at: nil), .smart(at: CGPoint(x: 0.2, y: 0.2)), .pinch(by: 0.5, at: nil),
            .wheel(points: 50, at: nil, fingers: true), .wheel(points: 50, at: nil, fingers: false),
            .pan(by: CGVector(dx: 10, dy: 10)),
        ]
        for input in inputs { XCTAssertNil(zoom.reduce(input), "\(input)") }
        XCTAssertEqual(zoom.phase, .flying)
        _ = zoom.reduce(.landed)
        XCTAssertEqual(zoom.reduce(.zoomIn), .spring(to: 1.25, seconds: AnnotatorZoom.stepSeconds))
    }

    func testAKeyOrAMouseWheelsNotchStopsAtTheFit() {
        var zoom = landed()
        XCTAssertNil(zoom.reduce(.zoomOut))
        XCTAssertNil(zoom.reduce(.wheel(points: -50, at: nil, fingers: false)))
        XCTAssertNil(zoom.reduce(.fit))
        settle(&zoom, zoom.reduce(.zoomIn))
        let out = zoom.reduce(.wheel(points: -200, at: nil, fingers: false))
        XCTAssertEqual(target(out), 1)
        XCTAssertEqual(seconds(out), AnnotatorZoom.stepSeconds)
        settle(&zoom, out)
        XCTAssertNil(zoom.reduce(.zoomOut))
        assertEqual(zoom.frame, fitted)
    }

    func testOnlyAHandPullsBelowTheFitAndNoFurtherThanHalfOfIt() {
        var zoom = landed()
        let pull = zoom.reduce(.pinch(by: -0.3, at: nil))
        XCTAssertEqual(target(pull)!, 0.7, accuracy: 1e-9)
        XCTAssertEqual(seconds(pull), AnnotatorZoom.trackingSeconds)
        XCTAssertEqual(target(zoom.reduce(.wheel(points: -20, at: nil, fingers: true)))!, 0.7 * exp(-0.2), accuracy: 1e-9)
        XCTAssertEqual(target(zoom.reduce(.pinch(by: -0.9, at: nil))), AnnotatorZoom.minLevel)
        // The frame shrinks by a part of the pull, which is the give a hand pulls against.
        _ = zoom.reduce(.tick(0.5))
        XCTAssertEqual(zoom.frame.width, fitted.width * (1 - 0.5 * AnnotatorZoom.overpull), accuracy: 1e-9)
    }

    func testAPullSpringsBackWhenTheFingersLift() {
        var zoom = landed()
        _ = zoom.reduce(.pinch(by: -0.3, at: CGPoint(x: 0.1, y: 0.9)))
        _ = zoom.reduce(.tick(0.85))
        XCTAssertEqual(zoom.reduce(.lift), .spring(to: 1, seconds: AnnotatorZoom.stepSeconds))
        settle(&zoom, .spring(to: 1, seconds: 0))
        assertEqual(zoom.frame, fitted)
        XCTAssertNil(zoom.reduce(.lift))
    }

    func testAPullSpringsBackWhenTheSpringCatchesUpWithAHandThatStopped() {
        var zoom = landed()
        _ = zoom.reduce(.pinch(by: -0.3, at: nil))
        _ = zoom.reduce(.tick(0.7))
        XCTAssertEqual(zoom.reduce(.arrived), .spring(to: 1, seconds: AnnotatorZoom.stepSeconds))
    }

    func testTheLevelStopsEightTimesPastTheSideThatFillsTheRoomFirst() {
        var zoom = landed()
        for _ in 0..<40 { settle(&zoom, zoom.reduce(.zoomIn)) }
        XCTAssertNil(zoom.reduce(.zoomIn))
        XCTAssertEqual(zoom.level, room.height / fitted.height * AnnotatorZoom.maxCanvasZoom, accuracy: 1e-9)
        assertEqual(zoom.frame, room)
    }

    func testADoubleTapZoomsInTwiceAndThenBackToTheFit() {
        var zoom = landed()
        let tap = zoom.reduce(.smart(at: CGPoint(x: 0.2, y: 0.3)))
        XCTAssertEqual(tap, .spring(to: 2, seconds: AnnotatorZoom.stepSeconds))
        settle(&zoom, tap)
        XCTAssertEqual(zoom.reduce(.smart(at: CGPoint(x: 0.9, y: 0.9))), .spring(to: 1, seconds: AnnotatorZoom.stepSeconds))
        settle(&zoom, .spring(to: 1, seconds: 0))
        assertEqual(zoom.frame, fitted)
        XCTAssertEqual(zoom.center, Zoom.center)
    }

    func testAPanMovesOnlyAMagnifiedPictureAndLeavesTheFrame() {
        var zoom = landed()
        XCTAssertNil(zoom.reduce(.pan(by: CGVector(dx: 0, dy: 30))))
        // At 2 the width is still growing and the height is magnified past the room.
        settle(&zoom, zoom.reduce(.smart(at: nil)))
        XCTAssertEqual(zoom.camera.width, 1)
        XCTAssertGreaterThan(zoom.camera.height, 1)
        let frame = zoom.frame
        XCTAssertNil(zoom.reduce(.pan(by: CGVector(dx: 30, dy: 0))), "the whole width is in view")
        let before = zoom.center
        guard case .movePicture(let picture)? = zoom.reduce(.pan(by: CGVector(dx: 0, dy: 30))) else {
            return XCTFail("a pan down did not move the picture")
        }
        // The content follows the fingers, so the middle of what is in view moves up the image.
        XCTAssertEqual(zoom.center.y, before.y - 30 / picture.height, accuracy: 1e-9)
        XCTAssertEqual(picture, zoom.picture)
        XCTAssertEqual(zoom.frame, frame)
        for _ in 0..<100 { _ = zoom.reduce(.pan(by: CGVector(dx: 0, dy: 30))) }
        XCTAssertNil(zoom.reduce(.pan(by: CGVector(dx: 0, dy: 30))), "the top of the image is in view")
        XCTAssertEqual(Zoom.visible(center: zoom.center, camera: zoom.camera).minY, 0, accuracy: 1e-9)
    }

    func testTheCaretIsBroughtJustIntoView() {
        var zoom = landed()
        let image = CGSize(width: 1600, height: 1200)
        let caret = CGRect(x: 800, y: 1100, width: 2, height: 20)
        XCTAssertNil(zoom.reduce(.reveal(caret, image: image)), "the whole image is in view")
        settle(&zoom, zoom.reduce(.pinch(by: 3, at: nil)))
        XCTAssertEqual(zoom.level, 4)
        guard case .movePicture? = zoom.reduce(.reveal(caret, image: image)) else { return XCTFail("the caret was not revealed") }
        // A line's height of room below it, and no more.
        let visible = Zoom.visible(center: zoom.center, camera: zoom.camera)
        XCTAssertEqual(visible.maxY, (caret.maxY + caret.height) / image.height, accuracy: 1e-9)
        XCTAssertNil(zoom.reduce(.reveal(caret.offsetBy(dx: 0, dy: -100), image: image)), "already in view")
    }

    func testTheCardLeavesFromTheFittedFrameAndNothingZoomsOnTheWay() {
        var zoom = landed()
        settle(&zoom, zoom.reduce(.smart(at: CGPoint(x: 0.1, y: 0.1))))
        settle(&zoom, zoom.reduce(.pinch(by: 1, at: CGPoint(x: 0.95, y: 0.05))))
        XCTAssertNotEqual(zoom.frame, fitted)
        let fit = zoom.reduce(.close)
        XCTAssertEqual(fit, .spring(to: 1, seconds: AnnotatorZoom.fitToCloseSeconds))
        XCTAssertEqual(zoom.phase, .closing)
        _ = zoom.reduce(.tick(1.5))
        for input: AnnotatorZoom.Input in [.zoomIn, .pinch(by: 1, at: nil), .smart(at: nil), .lift, .arrived,
                                           .pan(by: CGVector(dx: 0, dy: 20))] {
            XCTAssertNil(zoom.reduce(input), "\(input)")
        }
        _ = zoom.reduce(.tick(1))
        assertEqual(zoom.frame, fitted)
    }

    func testACloseAtTheFitAsksForNoSpring() {
        var zoom = landed()
        XCTAssertNil(zoom.reduce(.close))
        XCTAssertEqual(zoom.phase, .closing)
    }

    func testTheNextImageOpensAtItsFitWithTheSameEdgePull() {
        var zoom = landed()
        settle(&zoom, zoom.reduce(.smart(at: CGPoint(x: 0.1, y: 0.1))))
        _ = zoom.reduce(.close)
        let next = CGRect(x: 100, y: 200, width: 300, height: 200)
        XCTAssertNil(zoom.reduce(.prepare(fitted: next, room: room)))
        XCTAssertEqual(zoom.phase, .flying)
        XCTAssertEqual(zoom.level, 1)
        XCTAssertEqual(zoom.frame, next)
        XCTAssertEqual(zoom.center, Zoom.center)
        XCTAssertEqual(zoom.edge, edge)
    }

    /// Random inputs, through a spring that ticks part of the way, is aimed somewhere else
    /// mid-way, and arrives, from images of random sizes and places in the room.
    func testRandomSequencesKeepTheRules() {
        let room = CGRect(x: 0, y: 100, width: 1400, height: 800)
        let image = CGSize(width: 1600, height: 1000)
        var pulls = 0, pans = 0, reveals = 0, zoomedCloses = 0, refused = 0, landings = 0
        for seed in 0..<1000 {
            var rng = SeededGenerator(seed: UInt64(seed))
            var zoom = AnnotatorZoom()
            zoom.edge = AnnotatorZoom.EdgePull(band: .random(in: 0...400, using: &rng), pull: .random(in: 0...1, using: &rng))
            var fitted = CGRect.zero
            /// The level the spring is carrying the level to, if it is moving.
            var spring: CGFloat?
            var trace: [String] = []
            func fail(_ message: String) {
                XCTFail("seed \(seed): \(message)\n" + trace.joined(separator: "\n"))
            }
            func cap() -> CGFloat {
                min(max(1, room.width / fitted.width), max(1, room.height / fitted.height)) * AnnotatorZoom.maxCanvasZoom
            }
            func cursor() -> CGPoint? {
                Bool.random(using: &rng) ? nil : CGPoint(x: .random(in: -0.2...1.2, using: &rng), y: .random(in: -0.2...1.2, using: &rng))
            }
            func check(_ effect: Effect?, after input: AnnotatorZoom.Input, phase: AnnotatorZoom.Phase) {
                trace.append("\(input) -> \(effect.map { "\($0)" } ?? "nil")")
                switch effect {
                case .spring(let to, let seconds)?:
                    if case .close = input {
                        if to != 1 || seconds != AnnotatorZoom.fitToCloseSeconds { fail("the close springs to \(to)") }
                    } else if phase != .landed {
                        fail("\(input) moved the zoom in \(phase)")
                    }
                    if to > cap() + 1e-9 { fail("aimed past the cap at \(to)") }
                    if to < AnnotatorZoom.minLevel { fail("aimed below half the fit at \(to)") }
                    let hand: Bool
                    switch input {
                    case .pinch: hand = true
                    case .wheel(_, _, let fingers): hand = fingers
                    default: hand = false
                    }
                    if !hand && to < 1 { fail("\(input) aimed below the fit at \(to)") }
                    if seconds != (hand ? AnnotatorZoom.trackingSeconds : (input == .close ? AnnotatorZoom.fitToCloseSeconds : AnnotatorZoom.stepSeconds)) {
                        fail("\(input) springs for \(seconds) s")
                    }
                    if [.lift, .arrived].contains(input), to != 1 { fail("\(input) springs to \(to), not the fit") }
                    if to < 1 { pulls += 1 }
                    spring = to
                case .place(let frame, let picture)?:
                    if !room.insetBy(dx: -1e-6, dy: -1e-6).contains(frame) { fail("\(frame) left the room") }
                    if picture.minX > 1e-6 || picture.minY > 1e-6 || picture.maxX < frame.width - 1e-6 || picture.maxY < frame.height - 1e-6 {
                        fail("\(picture) does not cover \(frame.size)")
                    }
                    if zoom.level >= 1 {
                        let w = zoom.window.width * zoom.camera.width, h = zoom.window.height * zoom.camera.height
                        if abs(w - zoom.level) > 1e-9 || abs(h - zoom.level) > 1e-9 { fail("\(w) by \(h) at level \(zoom.level)") }
                    }
                    if zoom.level == 1, frame != fitted {
                        let off = [frame.minX - fitted.minX, frame.minY - fitted.minY, frame.width - fitted.width, frame.height - fitted.height]
                        if off.contains(where: { abs($0) > 1e-6 }) { fail("\(frame) at the fit is not \(fitted)") }
                    }
                case .movePicture?:
                    if zoom.camera.width <= 1, zoom.camera.height <= 1 { fail("\(input) moved a picture with nothing hidden") }
                    if case .pan = input { pans += 1 } else { reveals += 1 }
                case nil:
                    switch input {
                    case .prepare, .landed, .tick, .arrived, .close: break
                    default: if phase != .landed { refused += 1 }
                    }
                }
            }
            func send(_ input: AnnotatorZoom.Input) {
                let phase = zoom.phase
                check(zoom.reduce(input), after: input, phase: phase)
            }
            func prepare() {
                let w = CGFloat.random(in: 200...1000, using: &rng), h = CGFloat.random(in: 150...600, using: &rng)
                fitted = CGRect(x: .random(in: room.minX...(room.maxX - w), using: &rng),
                                y: .random(in: room.minY...(room.maxY - h), using: &rng), width: w, height: h)
                send(.prepare(fitted: fitted, room: room))
                spring = nil
                send(.tick(1))
                // Most flights land before anything else happens; the rest meet inputs on the way.
                if Int.random(in: 0..<5, using: &rng) > 0 {
                    landings += 1
                    send(.landed)
                }
            }
            prepare()
            for _ in 0..<80 {
                switch Int.random(in: 0..<25, using: &rng) {
                case 0: prepare()
                case 1:
                    if zoom.phase == .flying { landings += 1 }
                    send(.landed)
                case 2, 3: send(.zoomIn)
                case 4: send(.zoomOut)
                case 5: send(.fit)
                case 6: send(.smart(at: cursor()))
                case 7, 8, 9: send(.pinch(by: .random(in: -0.6...1.5, using: &rng), at: cursor()))
                case 10: send(.wheel(points: .random(in: -120...120, using: &rng), at: cursor(), fingers: .random(using: &rng)))
                case 11: send(.lift)
                case 12, 13, 14: send(.pan(by: CGVector(dx: .random(in: -80...80, using: &rng), dy: .random(in: -80...80, using: &rng))))
                case 15, 16:
                    let caret = CGRect(x: .random(in: 0...image.width, using: &rng), y: .random(in: 0...image.height, using: &rng),
                                       width: 2, height: .random(in: 10...40, using: &rng))
                    send(.reveal(caret, image: image))
                case 17, 18, 19:
                    // Part of the way.
                    guard let to = spring else { continue }
                    send(.tick(zoom.level + (to - zoom.level) * .random(in: 0.1...0.9, using: &rng)))
                case 20, 21, 22, 23:
                    guard let to = spring else { continue }
                    spring = nil
                    send(.tick(to))
                    send(.arrived)
                default:
                    // The card leaves: the fit, carried all the way, and the frame is where it opened.
                    guard zoom.phase == .landed else { continue }
                    if zoom.level != 1 { zoomedCloses += 1 }
                    let phase = zoom.phase
                    let fit = zoom.reduce(.close)
                    check(fit, after: .close, phase: phase)
                    if fit != nil {
                        send(.tick(zoom.level + (1 - zoom.level) * 0.5))
                        send(.tick(1))
                    }
                    spring = nil
                    // A level within a thousandth of the fit asks for no fit: under half a point.
                    if fit == nil, abs(zoom.level - 1) > 0.001 { fail("the card leaves at level \(zoom.level)") }
                    let f = zoom.frame
                    if fit != nil, [f.minX - fitted.minX, f.minY - fitted.minY, f.width - fitted.width, f.height - fitted.height].contains(where: { abs($0) > 1e-6 }) {
                        fail("the card leaves from \(f), not \(fitted)")
                    }
                }
            }
        }
        // The sequences reached what they are meant to.
        XCTAssertGreaterThan(pulls, 600)
        XCTAssertGreaterThan(pans, 400)
        XCTAssertGreaterThan(reveals, 150)
        XCTAssertGreaterThan(zoomedCloses, 350)
        XCTAssertGreaterThan(refused, 10000)
        XCTAssertGreaterThan(landings, 2000)
    }
}
