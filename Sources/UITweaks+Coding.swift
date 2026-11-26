import Foundation

extension UITweaks: Codable {
    /// Set on the encoder that writes settings.json. There `ui` holds only the values that differ
    /// from the defaults, so a default tuned in a later build reaches a file an earlier one wrote.
    /// Every other encoding is whole, since `Settings.load` merges a file over it.
    static let differencesOnly = CodingUserInfoKey(rawValue: "vignette.ui.differencesOnly")!

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Each group reads its own keys from the one flat object, and leaves the others' alone.
    init(from decoder: Decoder) throws {
        stack = try Stack(from: decoder)
        labs = try Labs(from: decoder)
        annotator = try Annotator(from: decoder)
        editor = try Editor(from: decoder)
        liveInk = try LiveInk(from: decoder)
    }

    /// Every tweak under its own name, flat, in the groups' order. Mirror walks the properties, so a
    /// new tweak needs nothing here.
    var fields: [(name: String, value: Any)] {
        Mirror(reflecting: self).children.flatMap { group in
            Mirror(reflecting: group.value).children.compactMap { child in child.label.map { ($0, child.value) } }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        let differencesOnly = encoder.userInfo[Self.differencesOnly] as? Bool ?? false
        for (field, fallback) in zip(fields, UITweaks().fields) {
            guard let value = field.value as? any Encodable else { continue }
            if differencesOnly, Self.same(field.value, fallback.value) { continue }
            try container.encode(value, forKey: Key(stringValue: field.name))
        }
    }

    /// Equal, counting floating-point noise as equal: a slider's steps leave values such as
    /// 0.30000000000000004 where it showed 0.3, and written as a difference that would pin the
    /// default it equals.
    static func same(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? Double, let y = b as? Double { return abs(x - y) <= 1e-9 * max(1, abs(x), abs(y)) }
        guard let x = a as? AnyHashable, let y = b as? AnyHashable else { return false }
        return x == y
    }
}
