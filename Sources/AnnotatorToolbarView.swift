import AppKit
import SwiftUI

struct ToolbarView: View {
    @ObservedObject var model: AnnotatorToolbar.Model
    let onTool: (EditorCore.Tool) -> Void
    let onDone: () -> Void
    let onSend: (AgentDestination) -> Void
    let onTargetMenu: () -> Void
    let onFocusMessage: () -> Void
    let onTargetFrame: (CGRect) -> Void
    let onPins: () -> Void
    let onPinsFrame: (CGRect) -> Void
    /// The bar's width changed. A control coming or going opens or closes in the row, so the
    /// width moves on every frame of the spring, and the panel grows with it.
    let onWidth: () -> Void
    let onMessageEnd: () -> Void
    let onClose: () -> Void
    @FocusState var focused: Bool
    /// The control the pointer is on, and the one whose tooltip is up (`tip`).
    @State private var tipOver: AnnotatorToolbar.Model.Control?
    @State private var tipShown: AnnotatorToolbar.Model.Control?
    @State private var tipWait: DispatchWorkItem?
    @State private var tipLeft = Date.distantPast
    /// The message field's height as its text needs it. The box springs to it (`GrowingField`).
    @State var fieldHeight: CGFloat = 30
    @State var targetHovered = false
    /// The message field is being typed in.
    var typing: Bool { focused && model.keyed }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) var displayScale

    /// How far past a control its presses reach: to the bar's top and bottom edges, which are 7 pt
    /// from a 30 pt control, and into the gaps beside it. Not past the bar: the panel is clear there,
    /// and the window server passes a press on a clear pixel to the window behind.
    static let slop = EdgeInsets(top: 7, leading: 2, bottom: 7, trailing: 2)
    static let spacing: CGFloat = 2
    /// The tools sit 2 pt apart, so each takes half the gap.
    private static let toolSlop = EdgeInsets(top: 7, leading: 1, bottom: 7, trailing: 1)

    /// The widest the target's project name is drawn. Past it the name is cut, so a long folder name
    /// cannot stretch the bar.
    static let targetNameMax: CGFloat = 132

    /// The Comment tool's icon: the outline of the teardrop the tool places, its tip at the bottom left,
    /// as wide and as heavy as the 14 pt medium symbols beside it, as a template image.
    static let commentIcon: NSImage = {
        let side: CGFloat = 13.5, line: CGFloat = 1.4, canvas: CGFloat = 16
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let inset = (canvas - side) / 2 + line / 2
            let body = CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
            let r = body.width / 2
            let path = CGPath(roundedRect: body, cornerWidth: r, cornerHeight: r, transform: nil)
                .union(CGPath(rect: CGRect(x: body.minX, y: body.maxY - r, width: r, height: r), transform: nil))
            ctx.addPath(path)
            ctx.setLineWidth(line)
            ctx.setLineJoin(.miter)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Comment"
        return image
    }()

    /// The message field's width in the bar, and the most lines it grows to while it is typed in.
    static let messageWidth: CGFloat = 220
    static let messageLines = 6

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(EditorCore.Tool.allCases, id: \.self) { tool in
                Button { onTool(tool) } label: {
                    Group {
                        if let symbol = tool.symbol { Image(systemName: symbol) } else { Image(nsImage: Self.commentIcon).renderingMode(.template) }
                    }
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 30)
                        // Grey, not the accent: blue belongs to the one action at the end of the bar.
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(model.tool == tool ? Color.primary.opacity(0.16) : .clear))
                        // In the label, since a button acts only on presses on its label.
                        .padding(Self.toolSlop)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TactileButtonStyle(shape: .rounded, hitSlop: Self.toolSlop))
                .padding(Self.toolSlop.negated)
                .modifier(FocusRing(on: model.focus == .tool(tool)))
                .modifier(TipSpot(control: .tool(tool), text: "\(tool.label) (\(String(tool.key).uppercased()))", hover: tip))
            }
            if model.pinCount > 0 {
                pinsButton
                    .modifier(FocusRing(on: model.focus == .pins))
                    .modifier(TipSpot(control: .pins, text: "Pins", hover: tip))
                    .transition(Self.slot)
            }
            Divider().frame(height: 20).padding(.horizontal, 6)
            // One slot per control rather than one branch per offer, so a control two offers share
            // (Copy, the message field, the filled button) moves and restyles when the offer changes,
            // instead of fading out in one place while its twin fades in at another.
            let offer = model.offer, controls = model.controls
            if controls.contains(.copy) {
                copyButton(filled: offer.destination == nil)
                    .modifier(FocusRing(on: model.focus == .copy))
                    .modifier(Resting(while: model.sending))
                    .padding(.trailing, offer.offersTarget ? 6 : 0)
                    .transition(Self.slot)
            }
            // With a message field beside it, the target sits inside the field's box, so the two
            // read as one control. It draws above the field, whose box reaches under it.
            let joined = offer.offersTarget && offer.destination != nil
            if offer.offersTarget {
                // In the box, it stays in the box's top row, rising out of the bar with it.
                FollowsFieldTop(growth: fieldGrowth, following: joined) {
                    targetMenu(offer.destination, joined: joined)
                }
                    .modifier(FocusRing(on: model.focus == .target && !joined))
                    .modifier(Resting(while: model.sending))
                    .padding(.trailing, joined ? 0 : 4)
                    .zIndex(1)
                    .transition(Self.slot)
            }
            if let destination = offer.destination {
                messageField(sessionRoom: joined ? Self.targetWidth(nameWidth: targetNameWidth(offer.destination)) + Self.spacing : 0) { onSend(destination) }
                    .modifier(Resting(while: model.sending))
                    .padding(.trailing, 4)
                actionButton(offer.isSend ? "Send" : "Reply", key: offer.isSend ? "⌘↩" : "↩",
                             logo: offer.isSend ? nil : destination.client) { onSend(destination) }
                    .modifier(FocusRing(on: model.focus == .action))
                    .modifier(Resting(while: model.nothingToReply))
                    .contentShape(Rectangle())
                    .modifier(TipSpot(control: .action, text: model.nothingToReply ? AnnotatorToolbar.Model.nothingToReplyTip : nil, hover: tip))
            }
        }
        .padding(.horizontal, 7)
        .frame(height: AnnotatorToolbar.height)
        // Controls coming or going while the bar changes width are cut at its sides. Above and below
        // stay open, for the message field growing down past the bar.
        .mask { Rectangle().padding(.vertical, -(AnnotatorToolbar.messageRoom + AnnotatorToolbar.padding)) }
        .background { glass }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in onWidth() }
        .padding(AnnotatorToolbar.padding)
        // In: rises a little and settles on a spring. Out: a short fade while it sinks back.
        .opacity(model.shown ? 1 : 0)
        .scaleEffect(model.shown ? 1 : 0.94, anchor: .top)
        .offset(y: model.shown ? 0 : 8)
        .animation(entrance, value: model.shown)
        // Room above and below for the field to grow into, outside the entrance's scale.
        .padding(.vertical, AnnotatorToolbar.messageRoom)
        .onChange(of: model.messageAsks) { focused = true }
        // Centred in a panel that may be wider than the bar.
        .frame(maxWidth: .infinity)
        // A change of offer springs the bar to its new width about its centre, which stays under
        // the image. The centring is inside the spring: outside it, the bar jumped to its new place
        // and only its width sprang. The panel already has the room (`AnnotatorToolbar.position`).
        .animation(Anim.spring(0.35 * Settings.shared.motionScale), value: model.offer)
        .overlayPreferenceValue(TipSpots.self) { spots in
            GeometryReader { geometry in
                if let shown = tipShown, let spot = spots[shown], let text = spot.text {
                    // Under the control, or over it when the Dock leaves no room below the bar.
                    TipPlacement(target: geometry[spot.anchor], below: model.roomBelow > 40) {
                        TipLabel(text: text)
                    }
                    .id(shown)
                    .transition(.opacity.animation(Anim.spring(0.15 * Settings.shared.motionScale)))
                }
            }
            .allowsHitTesting(false)
        }
        .onChange(of: model.presses) { hideTip() }
        .onChange(of: model.shown) { hideTip() }
    }

    /// What VoiceOver says of the Pins button: "3", or "2 open, 1 resolved".
    private var pinsValue: String {
        let resolved = model.pinCount - model.openPinCount
        return resolved == 0 ? "\(model.pinCount)" : "\(model.openPinCount) open, \(resolved) resolved"
    }

    /// How many pins are open, or a checkmark once every one is resolved. A press lists them all
    /// (`EditorView.showPinList`).
    private var pinsButton: some View {
        Button { onPins() } label: {
            HStack(spacing: 6) {
                Group {
                    if model.openPinCount > 0 { Text("\(model.openPinCount)") } else { Image(systemName: "checkmark") }
                }
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(Color.primary.opacity(0.12)))
                Text("Pins")
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 6)
            .frame(height: 30)
            .padding(Self.toolSlop)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle(shape: .rounded, hitSlop: Self.toolSlop))
        .padding(Self.toolSlop.negated)
        .accessibilityLabel("Pins")
        .accessibilityValue(pinsValue)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onPinsFrame($0) }
    }

    /// The pointer came onto a control or left it. Like AppKit's, a tooltip comes up after the pointer
    /// has rested a second, and while one is up, or was a moment ago, the next comes up at once.
    func tip(_ control: AnnotatorToolbar.Model.Control, _ inside: Bool) {
        if inside {
            tipOver = control
            tipWait?.cancel()
            if tipShown != nil || Date().timeIntervalSince(tipLeft) < 0.5 {
                tipShown = control
                return
            }
            let wait = DispatchWorkItem { if tipOver == control { tipShown = control } }
            tipWait = wait
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: wait)
        } else if tipOver == control {
            if tipShown != nil { tipLeft = Date() }
            hideTip()
        }
    }

    private func hideTip() {
        tipWait?.cancel()
        tipOver = nil
        tipShown = nil
    }

    /// A control an offer adds or takes away. Its width grows from nothing as it comes and shrinks to
    /// nothing as it goes, on the offer's spring, so the controls beside it move with it: placed at its
    /// full width at once, it was drawn over the message field still sliding out of its way. It fades
    /// in once it has begun to open, and out before it is cut.
    private static var slot: AnyTransition {
        AnyTransition.modifier(active: Reveal(fraction: 0), identity: Reveal(fraction: 1)).combined(with: words)
    }

    /// Words giving way to others in one place: the old ones leave quickly, and the new ones fade in
    /// a moment later.
    static var words: AnyTransition {
        let motion = Settings.shared.motionScale
        return .asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.15 * motion).delay(0.1 * motion)),
                           removal: .opacity.animation(.easeOut(duration: 0.08 * motion)))
    }

    /// The target's name giving way to the next: the old one goes at once and the new one comes in
    /// while the name's width is still springing, so the box is never empty for long.
    static var nameSwap: AnyTransition {
        let motion = Settings.shared.motionScale
        return .asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.12 * motion).delay(0.05 * motion)),
                           removal: .opacity.animation(.easeOut(duration: 0.06 * motion)))
    }

    /// The bar's background: a blur of what is behind it under a neutral gray, since a material alone
    /// takes on the picture's colour, with a faint light along the top edge and a hairline outside it
    /// so the edge holds against a light picture as well as a dark one.
    private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let dark = colorScheme == .dark
        return shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(Color(white: dark ? 0.14 : 0.95).opacity(0.72)))
            .overlay(shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(dark ? 0.2 : 0.6), location: 0),
                                                              .init(color: .white.opacity(dark ? 0.05 : 0.2), location: 0.5),
                                                              .init(color: .white.opacity(dark ? 0.08 : 0.3), location: 1)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(shape.inset(by: -0.5).strokeBorder(.black.opacity(dark ? 0.35 : 0.12), lineWidth: 0.5))
    }


    private var entrance: Animation {
        let scale = Settings.shared.motionScale
        guard scale > 0 else { return .linear(duration: 0) }
        return model.shown ? .spring(response: 0.45 * scale, dampingFraction: 0.72) : Anim.spring(0.18 * scale)
    }
}

/// What went wrong with a send and what to do about it, in the popover on the button.
struct FailureReason: View {
    let text: String
    var body: some View {
        Label {
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        } icon: {
            // Two colours, since a red fill with the mark cut out of it disappears on a dark popover.
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette).foregroundStyle(.white, Color(nsColor: .systemRed))
        }
        .frame(width: 260, alignment: .leading)
        .padding(12)
    }
}

/// Where each control's tooltip goes, and what it says.
/// The I-beam over the message field. A field shows it itself only in the key window, and the bar's
/// panel is key only while the field is typed in.
struct IBeam: ViewModifier {
    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            switch phase {
            case .active: NSCursor.iBeam.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}
