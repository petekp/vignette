import CoreGraphics
import Foundation

extension EditorCore {
    @discardableResult
    mutating func press(_ x: CGFloat, _ y: CGFloat, _ modifiers: Modifiers = [], count: Int = 1, time: TimeInterval = 0) -> [Effect] {
        reduce(.pointerPressed(Pointer(location: CGPoint(x: x, y: y), modifiers: modifiers, time: time), clickCount: count))
    }

    @discardableResult
    mutating func dragTo(_ x: CGFloat, _ y: CGFloat, _ modifiers: Modifiers = [], time: TimeInterval = 1) -> [Effect] {
        reduce(.pointerDragged(Pointer(location: CGPoint(x: x, y: y), modifiers: modifiers, time: time)))
    }

    @discardableResult
    mutating func release(_ x: CGFloat, _ y: CGFloat, _ modifiers: Modifiers = [], time: TimeInterval = 1) -> [Effect] {
        reduce(.pointerReleased(Pointer(location: CGPoint(x: x, y: y), modifiers: modifiers, time: time)))
    }

    @discardableResult
    mutating func move(_ x: CGFloat, _ y: CGFloat) -> [Effect] {
        reduce(.pointerMoved(Pointer(location: CGPoint(x: x, y: y))))
    }

    /// A press, a drag through the middle and on to `to`, and a release there: the effects of all four.
    @discardableResult
    mutating func drag(from: (CGFloat, CGFloat), to: (CGFloat, CGFloat), _ modifiers: Modifiers = []) -> [Effect] {
        press(from.0, from.1, modifiers)
            + dragTo((from.0 + to.0) / 2, (from.1 + to.1) / 2, modifiers)
            + dragTo(to.0, to.1, modifiers)
            + release(to.0, to.1, modifiers)
    }

    @discardableResult
    mutating func click(_ x: CGFloat, _ y: CGFloat, _ modifiers: Modifiers = [], count: Int = 1) -> [Effect] {
        press(x, y, modifiers, count: count) + release(x, y, modifiers, time: 0.05)
    }

    @discardableResult
    mutating func key(_ key: Key, _ modifiers: Modifiers = [], shift: Bool = false, isRepeat: Bool = false) -> [Effect] {
        reduce(.keyDown(key, shift ? modifiers.union(.shift) : modifiers, isRepeat: isRepeat))
    }
}
