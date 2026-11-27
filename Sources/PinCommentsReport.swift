import Foundation

/// A card's pins and comments as the `comments` command writes them for an agent. Each pin has its
/// `id`, `number` and place, in fractions of the image as `pins=` takes them, `resolved` when its ask
/// is done, with who resolved it and when, and each comment its
/// `id`, words, writer, session, time and `sentIn`, the sends that carried it. `sends` lists the
/// card's sends that reached their client (`Record.reachedClient`), oldest first, and `message` is the
/// newest one's message.
enum PinCommentsReport {
    static func object(file: URL, drawing: Drawing?, records: [ScreenshotRequests.Record]) -> [String: Any] {
        let reached = records.filter { $0.reachedClient == true }
        let sent = reached.map { (record: $0, at: $0.handedOver ?? $0.created) }.sorted { $0.at < $1.at }
        func carriers(of comment: UUID) -> [String] {
            sent.filter { $0.record.pins?.contains { $0.comments.contains(comment) } == true }.map(\.record.id)
        }
        let width = Double(drawing?.pixels.width ?? 1), height = Double(drawing?.pixels.height ?? 1)
        // A pin the editor is still placing has no number and no comment yet.
        let pins = (drawing?.pins ?? []).filter { $0.number > 0 }.map { pin -> [String: Any] in
            var item: [String: Any] = ["id": pin.id.uuidString, "number": pin.number,
                                       "x": Double(pin.extent.minX) / width, "y": Double(pin.extent.minY) / height]
            if case .area(let frame, let tip) = pin.place {
                item["w"] = Double(frame.width) / width
                item["h"] = Double(frame.height) / height
                item["corner"] = tip.rawValue
            }
            if let resolved = pin.resolved {
                var by: [String: Any] = ["resolver": resolved.agent ? "agent" : "person"]
                by["agentName"] = resolved.agentName
                by["at"] = resolved.at.map(Pin.Comment.written)
                item["resolved"] = by
            }
            item["comments"] = pin.comments.map { comment -> [String: Any] in
                var words: [String: Any] = ["id": comment.id.uuidString, "text": comment.text,
                                            "writer": comment.agent ? "agent" : "person", "sentIn": carriers(of: comment.id)]
                words["agentName"] = comment.agentName
                words["session"] = comment.session?.id
                words["sessionName"] = comment.sessionName
                words["at"] = comment.at.map(Pin.Comment.written)
                return words
            }
            return item
        }
        let sends = sent.map { send -> [String: Any] in
            var item: [String: Any] = ["id": send.record.id, "at": Pin.Comment.written(send.at), "status": send.record.status.rawValue,
                                       "to": send.record.cardTitle ?? send.record.destinationName,
                                       "agent": send.record.address.client.rawValue, "session": send.record.address.id]
            item["message"] = send.record.message
            return item
        }
        var object: [String: Any] = ["file": file.path, "pins": pins, "sends": sends]
        object["message"] = sent.last?.record.message
        return object
    }
}
