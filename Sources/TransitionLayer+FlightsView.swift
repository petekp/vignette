import SwiftUI

struct FlightsView: View {
    @ObservedObject var model: TransitionLayer.Model
    var body: some View {
        let ui = Settings.shared.data.ui
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.swallowRects) { swallow in
                Color.black.opacity(0.01)
                    .frame(width: swallow.frame.width, height: swallow.frame.height)
                    .position(x: swallow.frame.midX, y: swallow.frame.midY)
            }
            ForEach(model.flights) { f in
                FlightPicture(flight: f, ui: ui, aspect: f.aspect)
                    .modifier(Bow(center: CGPoint(x: f.frame.midX, y: f.frame.midY), path: f.path, previous: f.previousPath, blend: f.blend))
                    .opacity(f.opacity)
                    .position(x: f.frame.midX, y: f.frame.midY)
            }
        }
        .ignoresSafeArea()
    }
}

/// One flight's picture, with its shadow, marks, ring and caption. Animatable in the shape the
/// picture is drawn in, so the marks and a press's place on the picture follow that shape in every
/// frame as it moves between a card's aspect fill and the editor's picture.
private struct FlightPicture: View, Animatable {
    let flight: TransitionLayer.Flight
    let ui: UITweaks
    var aspect: CGFloat

    nonisolated var animatableData: CGFloat {
        get { aspect }
        set { aspect = newValue }
    }

    var body: some View {
        let f = flight
        let picture = CGSize(width: aspect, height: 1)
        return Image(nsImage: f.image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(aspect, contentMode: .fill)
            .frame(width: f.frame.width, height: f.frame.height)
            .background(Color(nsColor: Config.matte).opacity(f.look.matte))
            .clipShape(RoundedRectangle(cornerRadius: f.look.corner, style: .continuous))
            // The shadow of whichever end the flight is nearest, so nothing pops when the card or
            // the annotator window takes over. Cast by the clipped image, before the ring: a card
            // casts its shadow from the same shape, and the two have to match at the ends or the
            // shadow steps when one takes the other's place.
            .shadow(color: .black.opacity(f.look.shadowOpacity), radius: f.look.shadowRadius, y: f.look.shadowY)
            .marks(f.marks, picture: picture, corner: f.look.corner)
            // The card's ring travels with the image, and the annotator window carries it on.
            .overlay(ui.ring(cornerRadius: f.look.corner).inset(by: f.look.ringInset)
                .stroke(.white.opacity(ui.cardBorderOpacity * f.look.ring), lineWidth: ui.cardBorderWidth))
            // Before the bow, so the spot is where the picture is on screen, swell and all.
            .overlay(FlightSpot(id: f.id, picture: picture))
            // The agent's title, pinned to the picture's top-left corner, so it bows and swells with it.
            .overlay(alignment: .topLeading) {
                if let caption = f.caption { FlightCaption(caption: caption, frameWidth: f.frame.width, shown: !f.leavingAnnotator) }
            }
    }
}
