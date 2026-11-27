import Foundation

// MARK: A reply's answers on the person's pins

extension ReplyProtocol {
    /// The agent's words on one of the person's pins, named by the pin's id from `pins.json`, and whether
    /// they resolve it (`--resolve`). A bundle leaves `resolve` out when it is false.
    struct Comment: Codable, Equatable {
        let pin: UUID
        let text: String
        var resolve: Bool? = nil
    }

    /// How many answers one reply may carry: a request sends no more pins.
    static let maxComments = Pin.maxCount

    /// The pins a request sent, beside its `image.png`.
    static func pinsURL(in requestDirectory: URL) -> URL { requestDirectory.appendingPathComponent("pins.json") }

    /// The picture with the person's marks and no pins, which a request with pins stores beside
    /// `image.png`. A reply without its own image goes on it, so its live pins are not drawn twice.
    static func baseImageURL(in requestDirectory: URL) -> URL { requestDirectory.appendingPathComponent("base.png") }

    /// The pins a request sent, placed inside its `image.png`, as the helper and the acceptance
    /// check read them.
    static func sentPins(in requestDirectory: URL) -> [Pin] {
        guard let image = PixelSize(imageAt: requestDirectory.appendingPathComponent("image.png")) else { return [] }
        return requestPins(in: requestDirectory, image: image)
    }

    /// The pins `pins.json` in a request's directory holds, placed inside `image` and in number
    /// order, or none when it has no such file or the file does not read.
    static func requestPins(in requestDirectory: URL, image: PixelSize) -> [Pin] {
        guard let data = try? Data(contentsOf: pinsURL(in: requestDirectory)),
              let object = (try? DrawingJSON.object(from: data)) as? [String: Any],
              let list = object["pins"] as? [Any] else { return [] }
        return Pin.read(list, nextPin: nil, in: image) { _, _ in }.pins
    }

    /// The helper's `--comments` object: each key a pin's number as the line cites it, or its id,
    /// and each value the answer's words. `resolving` is `--resolve`'s list, the pins the answers
    /// resolve, each named as a key is and answered in the object. Throws the one thing wrong, naming the key.
    static func comments(answering object: Any?, on pins: [Pin], resolving: [String] = []) throws -> [Comment] {
        guard let answers = object as? [String: Any] else {
            throw MarkProblem("expected a JSON object of answers, each key a pin's number or id")
        }
        guard !answers.isEmpty else { throw MarkProblem("no answers in it") }
        guard answers.count <= maxComments else { throw MarkProblem("\(answers.count) answers; at most \(maxComments)") }
        let found = try answers.map { key, words -> (pin: Pin, text: String) in
            guard let pin = pins.first(where: { String($0.number) == key || $0.id == UUID(uuidString: key) }) else {
                throw MarkProblem("\(key) is not a pin the user sent")
            }
            do { return (pin, try MarkFields(item: ["text": words], unit: .fraction).text()) }
            catch { throw MarkProblem("\(key): \(error)") }
        }
        guard Set(found.map(\.pin.id)).count == found.count else { throw MarkProblem("two keys name the same pin") }
        let resolved = try Set(resolving.map { key -> UUID in
            guard let pin = pins.first(where: { String($0.number) == key || $0.id == UUID(uuidString: key) }) else {
                throw MarkProblem("--resolve names \(key), which is not a pin the user sent")
            }
            guard found.contains(where: { $0.pin.id == pin.id }) else {
                throw MarkProblem("--resolve names \(key), which has no answer; say what you did in --comments")
            }
            return pin.id
        })
        return found.sorted { $0.pin.number < $1.pin.number }.map {
            Comment(pin: $0.pin.id, text: $0.text, resolve: resolved.contains($0.pin.id) ? true : nil)
        }
    }

    /// `--resolve`'s value: pin numbers or ids, separated by commas.
    static func resolveList(_ value: String) throws -> [String] {
        let keys = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !keys.isEmpty else { throw MarkProblem("--resolve needs pin numbers or ids, separated by commas") }
        return keys
    }

    /// A bundle's `comments`, checked as `readBundle` checks marks. None when it has none.
    static func bundleComments(_ raw: Any?) throws -> [Comment] {
        guard let raw else { return [] }
        guard let list = raw as? [[String: Any]], !list.isEmpty, list.count <= maxComments else {
            throw Problem(.badPayload, "the bundle's comments must be a list of 1 to \(maxComments)")
        }
        let comments = try list.enumerated().map { index, item -> Comment in
            guard let pin = (item["pin"] as? String).flatMap(UUID.init(uuidString:)),
                  let text = try? MarkFields(item: item, unit: .fraction).text(),
                  let resolve = try? MarkFields(item: item, unit: .fraction).flag("resolve") else {
                throw Problem(.badPayload, "the bundle's comment \(index + 1) needs a pin id and text, and resolve true or false")
            }
            return Comment(pin: pin, text: text, resolve: resolve ? true : nil)
        }
        guard Set(comments.map(\.pin)).count == comments.count else {
            throw Problem(.badPayload, "the bundle answers one pin twice")
        }
        return comments
    }

    /// Refuses comments that answer a pin the request did not send, or a request kept without
    /// `base.png`, which has no live pins for them.
    static func check(_ comments: [Comment], requestDirectory: URL) throws {
        guard !comments.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: baseImageURL(in: requestDirectory).path) else {
            throw Problem(.badPayload, "this request was sent without pins an answer can go on")
        }
        let sent = Set(sentPins(in: requestDirectory).map(\.id))
        if let stranger = comments.first(where: { !sent.contains($0.pin) }) {
            throw Problem(.badPayload, "pin \(stranger.pin.uuidString) is not one this request sent")
        }
    }
}

extension Pin {
    /// This pin with `comments`' answer to it added as `author`'s comment, resolved by `author` when the
    /// answer resolves it.
    func answered(by comments: [ReplyProtocol.Comment], as author: AgentAuthor) -> Pin {
        var pin = self
        for answer in comments where answer.pin == id {
            pin.comments.append(author.comment(answer.text))
            pin.resolved = answer.resolve == true ? author.resolution : nil
        }
        return pin
    }
}
