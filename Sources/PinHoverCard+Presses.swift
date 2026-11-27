import AppKit

/// The view under a pin's card, filling the card's panel. The window server gives the panel the presses
/// on the pixels it draws, the card and its shadow, and passes the clear rest to what is behind it. This
/// hands each press on, on screen, saying whether it began on the card.
@MainActor
final class PinCardRoom: NSView {
    weak var card: PinHoverCard?
    var onPress: ((FlightPress.Event, _ onCard: Bool) -> Void)?
    private(set) var pressing = false
    private var onCard = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressing = true
        onCard = card.map { $0.frame.contains(convert(event.locationInWindow, from: nil)) } ?? false
        relay(event, .pressed(clickCount: event.clickCount))
    }

    override func mouseDragged(with event: NSEvent) {
        if pressing { relay(event, .dragged) }
    }

    override func mouseUp(with event: NSEvent) {
        guard pressing else { return }
        pressing = false
        relay(event, .released)
        card?.pressEnded()
    }

    private func relay(_ event: NSEvent, _ phase: FlightPress.Phase) {
        guard let window else { return }
        onPress?(FlightPress.Event(phase: phase, picture: nil, screen: window.convertPoint(toScreen: event.locationInWindow),
                                   modifiers: event.modifierFlags.rawValue, time: event.timestamp), onCard)
    }
}
