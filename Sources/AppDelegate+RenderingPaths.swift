import Foundation

extension AppDelegate {
    static func renderingPaths(_ urls: [URL]) -> String {
        let data = try? JSONEncoder().encode(urls.map(\.path))
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
