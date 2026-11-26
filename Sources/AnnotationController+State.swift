import AppKit

// MARK: The state report

extension AnnotationController {
    var stateJSON: [String: Any] {
        [
            "current": current?.url.path as Any,
            "windowVisible": window?.isVisible ?? false,
            "key": window?.isKeyWindow ?? false,
            "zoom": [zoom.window.width, zoom.window.height],
            "zoomLevel": zoom.level,
            "zoomPhase": zoom.phase.description,
            "canvasZoom": [zoom.camera.width, zoom.camera.height],
            "zoomAnchor": [zoom.anchor.x, zoom.anchor.y],
            "zoomCenter": [zoom.center.x, zoom.center.y],
            "room": StateReport.topLeft(zoom.room, primaryHeight: StateReport.primaryHeight),
            "frame": frameOnScreen.map { StateReport.topLeft($0, primaryHeight: StateReport.primaryHeight) } as Any,
            "toolbar": (toolbar.panel.isVisible ? StateReport.topLeft(toolbar.barFrame, primaryHeight: StateReport.primaryHeight) : nil) as Any,
            "title": titleFrameOnScreen.map { StateReport.topLeft($0, primaryHeight: StateReport.primaryHeight) } as Any,
            "sender": titleView.content?.sender?.words as Any,
            "titleInk": (titleFrameOnScreen == nil ? nil : ["ink": titleView.ink.rawValue, "source": inkSource as Any]) as Any,
            "toolbarFocus": toolbar.model.focus?.name as Any,
            "toolbarKey": toolbar.panel.isKeyWindow,
            "tool": toolbar.model.tool?.rawValue as Any,
            "offer": (current == nil ? nil : offerJSON) as Any,
            "keptPick": keptPick.map { kept -> [String: Any] in
                ["session": kept.session.id, "client": kept.session.client.rawValue,
                 "secondsLeft": max(0, Int(DestinationChoice.KeptPick.lasts - Date().timeIntervalSince(kept.sentAt)))]
            } as Any,
        ]
    }

    /// What the bar offers, and where its filled button sends: the session's id, client, project
    /// and why it is the session you came from, never its title.
    private var offerJSON: [String: Any] {
        let offer = toolbar.model.offer
        var json: [String: Any] = ["listed": toolbar.model.listed]
        switch offer {
        case .copy: json["kind"] = "copy"
        case .choose: json["kind"] = "choose"
        case .send: json["kind"] = "send"
        case .reply: json["kind"] = "reply"
        }
        if let destination = offer.destination {
            json["session"] = destination.id
            json["client"] = destination.client.rawValue
            json["project"] = destination.detail
            json["focus"] = destination.focus?.rawValue as Any
        }
        return json
    }
}
