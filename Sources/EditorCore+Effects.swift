import CoreGraphics
import Foundation

extension EditorCore {
    enum Effect: Equatable {
        /// The active tool changed; the toolbar shows it.
        case tool(Tool)
        case cursor(Cursor)
        /// Start the text view on this text mark, or move its caret when it is already there.
        case beginTyping(Mark.ID, Caret)
        /// Keep this key: a tool key pressed right after a box or an arrow was drawn. It is the note's
        /// first character if a character follows it.
        case holdKey
        /// The kept key and this one go to the text view, which types them into the note just begun.
        case passKeysToText
        /// The session is over: the text view goes, and the mark draws the text.
        case endTyping
        /// The press landed in the text being typed: the text view takes it and what follows it.
        case passPressToText
        /// Start the `handOverDelay` timer again from now.
        case scheduleTimer
        case cancelTimer
        /// The drawing for the host to store. With no marks, the host removes its file.
        case handOver(Drawing)
        /// The marks and pins on the clipboard in Vignette's own type, and as plain text the words of
        /// any texts among them and the pins' words.
        case copyItems(CopiedItems, text: String?)
        /// The drawing's rendering on the clipboard, the same as Done's.
        case copyDrawing(Drawing)
        /// Cmd+V: read the clipboard and answer with `paste`.
        case readClipboard
        /// The system beep: a key that cannot act, such as Cmd+V with an image on the clipboard.
        case beep
        case zoom(ZoomRequest)
        /// For VoiceOver.
        case announce(String)
        /// Undo or redo changed the message: the field shows these words.
        case message(String)
        /// Tab went past the last mark, or Shift+Tab past the first: the toolbar's controls come next.
        case leaveCanvas(backward: Bool)
        /// M or P: the message that goes with Send.
        case focusMessage
        /// Left or Right with nothing selected, nothing typed and no drag: the host opens the
        /// screenshot beside this one, or beeps.
        case page(Page, isRepeat: Bool)
        /// Ask the host to close the editor.
        case close
        /// The pin popover is now this, or closed with nil.
        case composer(Composer?)
        /// A click on a cluster: its pins, in number order, listed by the cluster at this rect in px.
        case showCluster([Pin.ID], at: CGRect)
        /// Render this drawing and finish.
        case done(Drawing)
        /// Render this drawing and send it; the editor stays open. A key's send has no destination:
        /// it goes where the toolbar's filled button sends.
        case send(Drawing, to: AgentDestination?)
    }

    enum Page: Equatable {
        case older, newer

        init?(_ key: Key) {
            switch key {
            case .left: self = .older
            case .right: self = .newer
            default: return nil
            }
        }
    }

    enum Caret: Equatable {
        /// At the character nearest this point.
        case at(CGPoint)
        case end
        case selectAll
    }

    enum Cursor: Equatable {
        case arrow, crosshair, iBeam, openHand, closedHand
        case resize(HandlePosition)
        /// The Comment tool's, over the picture: the crosshair, with a small pin in a person's colour.
        case comment(SRGB)
    }

    enum ZoomRequest: Equatable {
        case zoomIn, zoomOut, fit
        /// Twice as close at this point, or back to fit from anywhere closer.
        case smart(at: CGPoint)
    }
}
