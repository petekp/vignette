import Foundation

extension ReplyCommand {
    static let usage = """
    usage: reply --ticket <ticket.json> --marks <marks.json> [--image <your image>] [--title <text>] [--description <text>]
           reply --ticket <ticket.json> --comments <comments.json> [--marks <marks.json>] [--title <text>] [--description <text>]
           reply --ticket <ticket.json> --answer <answer.json>
           reply --ticket <ticket.json> --retry <bundle folder>

    Answers a Vignette screenshot request with a drawing of your own. Vignette sends a message
    containing "From Vignette:" that names the ticket.json, or an image with one beside it.
    The marks arrive on a new card the person can edit like their own drawing.

    The marks file is a JSON array. Every number is a fraction of the image: x,y is a shape's
    top-left corner or an arrow's tail, w,h its size, x2,y2 an arrow's head.

        [{"type": "ellipse",   "x": 0.12, "y": 0.30, "w": 0.20, "h": 0.10},
         {"type": "arrow",     "x": 0.50, "y": 0.50, "x2": 0.70, "y2": 0.60},
         {"type": "rectangle", "x": 0.10, "y": 0.10, "w": 0.30, "h": 0.20},
         {"type": "text",      "x": 0.10, "y": 0.80, "w": 0.50, "text": "This header should not scroll"}]

    At most \(AgentMark.maxCount) marks. They are drawn in the agent's colour, so the person can tell them from
    their own. Without --image the marks go on the picture you were sent. With it they go on yours, sent as a PNG of at most \(ReplyProtocol.maxImageBytes / 1_048_576) MB, and
    the marks may be an empty array. A JPEG or any other image macOS reads is converted.

    --comments answers the user's pins, which the message cites as "Pin 3: …". It is a JSON object,
    or a file holding one, with each key a pin's number or its id from the pins.json beside the
    image, and each value your answer to that pin:

        {"3": "Widened the shimmer band to 40% of the row", "5": "Fixed; it was the cache key"}

    Your answers join the user's pins on the new card, each one under the user's words, so answer
    there rather than drawing a note beside a pin. At most \(ReplyProtocol.maxComments) answers, one per pin, each at most
    \(MarkFields.maxTextLength) characters. Not with --image or --answer.

    --title and --description say what your reply shows. The editor shows the title above the
    image and the description under it, so you can say what the picture is without drawing it on.
    At most \(AgentTitle.maxTitle) and \(AgentTitle.maxDescription) characters, on one line each; longer text is cut at a
    word, and the JSON line names what was cut under "cut". Neither goes with --answer.

    A request drawn with live ink says so, and is answered on the window itself with --answer:
    your words take the place of the person's note, and each mark circles, points at or pulls
    focus to the words it names, found on the window as it looks when your reply arrives, so name
    words that are on screen after your change. At most \(LiveAnswer.maxMarks) marks, each label one to four words.
    A mark's "box", [x, y, w, h] in fractions of the picture you were sent, is used when its words
    are not found, so give one with a number or a price, which the capture can misread.

        {"say": "Moved the dates under the title and made them smaller.",
         "marks": [{"kind": "circle", "words": "October 12 to 18", "label": "moved"},
                   {"kind": "arrow", "words": "A week in Tuscany"}]}

    With --answer it waits until the answer is drawn, about a second. "notDrawn" then lists each
    mark whose words were not found, which the person does not see: say that finding in your own
    words instead.

    Prints one JSON line and exits 0 accepted, 1 not sent, 2 refused, or 3 unconfirmed. Not sent
    means an argument, a file or a mark is wrong, and "error" says which. Unconfirmed means
    Vignette never answered: the reply may or may not have arrived, so do not send a new one.
    Retry that exact reply instead, which can never make a second card. A retry that exits 1 sent
    nothing, but the first attempt may still have arrived, so do not send a new reply then either.
    """
}
