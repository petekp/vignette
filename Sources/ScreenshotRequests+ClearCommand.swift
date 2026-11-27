import Foundation

extension ScreenshotRequests {
    /// `vignette://requests[?clear=<id|all>]`. Listing says what is open; clearing stops a request
    /// taking new replies, cancels its unpublished imports, and removes only files Vignette owns.
    /// Published cards are the person's and are left alone.
    func run(clear: String?) {
        guard let clear, !clear.isEmpty else {
            for record in requests.values.sorted(by: { $0.created < $1.created }) {
                let count = replies.values.filter { $0.requestID == record.id }.count
                let why = record.detail.isEmpty ? "" : " \(record.detail)"
                Log.write("[requests] \(record.id) \(record.status.rawValue) \(record.destinationName) \(record.address.description) source=\(record.source) replies=\(count)\(why)")
            }
            Commands.ok("requests", "\(requests.count) requests, \(replies.count) replies")
            return
        }
        let targets = clear == "all" ? Array(requests.keys) : [clear]
        var cleared = 0
        var failures: [String] = []
        for id in targets {
            do { if try self.clear(id) { cleared += 1 } }
            catch { failures.append("\(id): \(error.localizedDescription)") }
        }
        if !failures.isEmpty {
            Commands.error("requests", .writeFailed, "cleared \(cleared); \(failures.joined(separator: "; "))")
            return
        }
        guard cleared > 0 else { Commands.error("requests", .missingFile, "no request \(clear)"); return }
        Commands.ok("requests", "cleared \(cleared)")
    }
}
