import Foundation

extension ScreenshotRequests {
    /// For each session, when its newest request was handed to it. A request cancelled in its grace
    /// period never was, and a request cleared afterwards still was.
    func sendHistory() -> [String: Date] {
        var history: [String: Date] = [:]
        for record in requests.values {
            guard let handedOver = record.handedOver else { continue }
            if let known = history[record.destinationID], known >= handedOver { continue }
            history[record.destinationID] = handedOver
        }
        return history
    }
}
