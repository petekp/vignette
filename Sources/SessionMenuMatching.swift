import Foundation

extension SessionMenu {
    /// The groups of `groups` whose rows match `query`, in the same order, except that a group with a
    /// running session comes before one of rows that start a session, so Return never starts one
    /// while a running session matches. A row matches when every word of the query is found,
    /// ignoring case and accents, in its title, its details, the words at its right or its group's
    /// header. A query with no words matches every row.
    static func matching(_ query: String, in groups: [Group]) -> [Group] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        let found = words.isEmpty ? groups : groups.compactMap { group in
            let rows = group.rows.filter { row in
                let text = fold([row.title, row.details, badge(of: row), group.header].compactMap { $0 }.joined(separator: " "))
                return words.allSatisfy { text.contains($0) }
            }
            return rows.isEmpty ? nil : Group(header: group.header, key: group.key, rows: rows)
        }
        let startsOnly = { (group: Group) in group.rows.allSatisfy(\.destination.startsProcess) }
        return found.filter { !startsOnly($0) } + found.filter(startsOnly)
    }

    /// The words a row shows at its right edge, or nil when it shows none.
    private static func badge(of row: Row) -> String? {
        switch row.activity {
        case .working: working
        case .lastActive(let ago): ago
        case nil: nil
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
