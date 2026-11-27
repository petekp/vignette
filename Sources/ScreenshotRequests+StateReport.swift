import Foundation

extension ScreenshotRequests {
    var stateJSON: [String: Any] {
        [
            "directory": root.path,
            "requests": requests.values.sorted { $0.created < $1.created }.map { record -> [String: Any] in
                var json: [String: Any] = ["id": record.id, "status": record.status.rawValue, "destination": record.destinationName,
                                           "address": record.address.description, "guard": record.addressGuard.rawValue, "source": record.source]
                if record.unchanged == true { json["unchanged"] = true }
                if let grace = self.grace(of: record.id) { json["graceMs"] = Int(max(0, grace.deadline - self.now()) * 1000) }
                if let watch = self.queueWatches[record.id] {
                    json["queuedLine"] = watch.line.id
                    if let shown = watch.shown { json["queuedReason"] = shown }
                }
                return json
            },
            "replies": replies.values.sorted { $0.id < $1.id }.map { reply -> [String: Any] in
                var json: [String: Any] = ["id": reply.id, "request": reply.requestID, "stage": reply.stage.rawValue,
                                           "file": reply.fileName, "marks": reply.marks.count, "deleted": reply.deleted]
                if let code = reply.errorCode { json["error"] = code }
                return json
            },
            "pendingImports": pendingImports,
        ]
    }
}
