import Foundation

extension SessionMenu {
    /// The groups of `menu.everyone` whose rows match `query`. A row matches when every word of the
    /// query is found, ignoring case and accents, in its title, its details, the words at its right or
    /// its group's header. Hyphens and underscores part the query's words as spaces do, so
    /// "lead-assignment" finds "Lead Assignment". A query with no words matches every row.
    ///
    /// The group whose best match ranks highest comes first, so the freshest match leads whatever its
    /// project, Other folders included, except that a group with a running session comes before one
    /// of rows that start a session, so Return never starts one while a running session matches. A
    /// group keeps its rows in the menu's order.
    static func matching(_ query: String, in menu: Menu) -> [Group] {
        let words = searchWords(in: query)
        let found = menu.everyone.compactMap { group -> Group? in
            let rows = group.rows.filter { row in
                let text = fold([row.title, row.details, badge(of: row), group.header].compactMap { $0 }.joined(separator: " "))
                return words.allSatisfy { text.contains($0) }
            }
            return rows.isEmpty ? nil : Group(header: group.header, key: group.key, rows: rows)
        }
        /// Running before rows that only start a session, then by the group's best-ranked row.
        func order(_ group: Group) -> (Int, Int) {
            (group.rows.allSatisfy(\.destination.startsProcess) ? 1 : 0, group.rows.compactMap { menu.rank[$0.id] }.min() ?? .max)
        }
        return found.sorted { order($0) < order($1) }
    }

    /// The words search looks for in `query`, folded: hyphens and underscores part them as spaces do.
    /// None means the query searches for nothing, and the menu shows its usual rows.
    static func searchWords(in query: String) -> [String] {
        fold(query).split { $0.isWhitespace || $0 == "-" || $0 == "_" }.map(String.init)
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
