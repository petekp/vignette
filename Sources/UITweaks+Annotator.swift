import Foundation

extension UITweaks {
    /// The annotator window's tweaks: its size, an agent's title above the image and the zoom
    /// (`TweakCatalog+Annotator.swift`).
    struct Annotator: Decodable, Equatable {
        // Annotator window
        var annotationMinWidth = 770.0
        var annotationMinHeight = 320.0
        var annotationCornerRadius = 16.0
        var annotationToolbarGap = 9.0   // the frame to the toolbar, the toolbar to the screen's bottom, and the frame to the stack
        var annotationScreenInset = 60.0
        // An agent's title above the image (`AgentTitleView`): screen pt, the same size at any zoom
        var agentSenderSize = 12.0       // the sender's line above the title: "From <sender>"
        var agentSenderLogoSize = 13.0
        var agentSenderLogoGap = 5.0     // between the logo and the sender's words
        var agentSenderGap = 4.0         // between the sender's line and the title under it
        var agentTitleSize = 17.0
        var agentDescriptionSize = 13.0
        var agentTitleLineGap = 2.0      // between the title and the description under it
        var agentTitleGap = 10.0         // between the block and the image's frame
        var agentTitleMinWidth = 300.0   // the narrowest it wraps at: about 45 characters of the description
        var agentTitleFade = 0.15        // in after the flight lands, out as it flies home
        var zoomEdgeBandPoints = 250.0   // how far from each edge of the picture a zoom holds that edge
        var zoomEdgePull = 0.6           // the part of that band in which the edge is held exactly
    }
}
