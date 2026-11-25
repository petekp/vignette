import AppKit
import SwiftUI

/// The bar's controls: Copy, the message field, the action buttons and the target menu.
extension ToolbarView {
    /// Copy: the drawing onto the clipboard and the editor closed. The filled button when there is
    /// nowhere to send.
    func copyButton(filled: Bool) -> some View {
        Button(action: onDone) {
            HStack(spacing: 6) {
                Text("Copy").font(.system(size: 13, weight: .semibold))
                keyText("↩", filled: filled)
            }
            .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(filled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.09)),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(Self.slop)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle(shape: .rounded, hoverScale: 1, hitSlop: Self.slop))
        .padding(Self.slop.negated)
        .modifier(TipSpot(control: .copy, text: "Copy your drawing and close the editor", hover: tip))
    }

    /// What goes with the drawing, typed in the bar. One line wide in the bar; while it is typed in
    /// it grows down past the bar's bottom, up to `messageLines` lines, and the bar keeps its size.
    /// Return and Cmd+Return send (`ToolbarPanel`), since typing a message is the intent to send it.
    /// Esc hands the keys back to the editor. In a field that took the keys on its own and is still
    /// empty, Return and Esc do what they do on the image (`Model.fieldReturn`).
    /// `sessionRoom` is how far the box reaches left past the field, under the target.
    func messageField(sessionRoom: CGFloat, send: @escaping () -> Void) -> some View {
        let grown = typing && !model.message.isEmpty
        let outline = FieldOutline(tallWidth: Self.messageWidth + Self.spacing + TargetShade.hairlineWidth / 2)
        let boxWidth = Self.messageWidth + sessionRoom
        return GrowingField(growth: fieldGrowth) {
            Color.clear
            // The text at its own height, always. A text field shorter than its text scrolls to its
            // caret, so while the box grew around it the text jumped up a line and back. The box
            // clips it instead (`FieldTextMask`).
            .overlay(alignment: .top) {
                TextField("Add a message", text: $model.message, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Font(FieldTextMask.font))
                    .lineLimit(typing ? 1...Self.messageLines : 1...1)
                    .focused($focused)
                    .onSubmit {
                        switch model.fieldReturn {
                        case .done: onDone()
                        case .send: if !model.sending { send() }
                        }
                    }
                    .onExitCommand { if model.fieldEscCloses { onClose() } else { onMessageEnd() } }
                    .onChange(of: model.message) { _, words in
                        if words.count > AnnotatorToolbar.Model.messageLimit { model.message = String(words.prefix(AnnotatorToolbar.Model.messageLimit)) }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, FieldTextMask.inset)
                    .frame(width: Self.messageWidth, alignment: .topLeading)
                    .frame(minHeight: 30)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        withAnimation(Anim.spring(0.25 * Settings.shared.motionScale)) { fieldHeight = height }
                    }
            }
            .modifier(FieldTextMask(outline: outline, width: boxWidth, textHeight: fieldHeight))
            // The part under the target takes no presses or hover, which are the target's.
            .background(alignment: .trailing) {
                ZStack {
                    outline.fill(Color.primary.opacity(0.09)).shadow(color: .black.opacity(grown ? 0.3 : 0), radius: 10, y: 4)
                    // Grown, it hangs past the bar over whatever is behind, so it takes a blur of that, as a
                    // popover does.
                    BehindWindowBlur(outline: outline).opacity(grown ? 1 : 0)
                }
                .frame(width: boxWidth)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                outline.stroke(Color.accentColor.opacity(typing ? 0.8 : 0), lineWidth: 1)
                    .frame(width: boxWidth)
                    .allowsHitTesting(false)
            }
            // The text field takes presses only on its text. Its padding and the room around it in
            // the bar start typing too, on the press, through the gesture behind the box. A gesture
            // on the text as well took the release of a quick click, and the text field then waited
            // for it with every other event queued behind, Esc included, until the next click.
            .modifier(IBeam())
        }
        .frame(width: Self.messageWidth, height: 30)
        .padding(Self.slop)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(pressToType)
                .modifier(IBeam())
        }
        .padding(Self.slop.negated)
        .animation(Anim.spring(0.25 * Settings.shared.motionScale), value: typing)
        .modifier(TipSpot(control: .message, text: typing ? nil : "Add a message (M)", hover: tip))
    }

    /// The message field's box as it grows. It may reach below its slot down to the bar's bottom edge,
    /// 7 pt under the bar's middle, and the room under the bar, less a margin that keeps it off the Dock.
    var fieldGrowth: FieldGrowth {
        FieldGrowth(height: fieldHeight, below: model.roomBelow + (AnnotatorToolbar.height - 30) / 2 - 8, scale: displayScale)
    }

    private var pressToType: some Gesture {
        DragGesture(minimumDistance: 0).onChanged { _ in if !typing { onFocusMessage() } }
    }

    /// Send or Reply: the filled button, with the agent's logo when it goes back to one. From the
    /// press it shows the send, and after a failure before the store it says "Not sent". Its label
    /// stays in the layout under both, so the button keeps its width and nothing beside it moves.
    /// It keeps its fill, since it is busy rather than disabled, and takes no clicks while sending.
    /// After a failure a click sends again.
    func actionButton(_ title: String, key: String, logo client: AgentClient?, action: @escaping () -> Void) -> some View {
        let motion = Settings.shared.motionScale
        let busy = model.sending || model.notSent
        return Button(action: action) {
            // Send and Reply are one button. Its words leave before the new ones come, in one place,
            // since two words drawn through each other read as neither.
            ZStack {
                HStack(spacing: 6) {
                    if let client { AgentLogo(client: client, template: true).frame(width: 13, height: 13) }
                    Text(title).font(.system(size: 13, weight: .semibold))
                    keyText(key, filled: true)
                }
                .id(title)
                .transition(Self.words)
            }
            .opacity(busy ? 0 : 1)
            .blur(radius: busy ? 4 : 0)
            .offset(y: model.sending ? -6 : 0)
            .overlay {
                if model.sending {
                    SendingGlyph(leaving: !model.shown).transition(.blurReplace)
                } else if model.notSent {
                    Text("Not sent").font(.system(size: 13, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .transition(.blurReplace)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(model.notSent ? Color(nsColor: .systemRed) : Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(Self.slop)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle(shape: .rounded, hoverScale: 1, hitSlop: Self.slop))
        .padding(Self.slop.negated)
        .allowsHitTesting(!model.sending)
        // The reason, attached to the button that failed, as a popover: it stays until a click
        // elsewhere, which also gives the button back.
        .popover(isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } }), arrowEdge: .bottom) {
            FailureReason(text: model.failure ?? "")
        }
        .keyframeAnimator(initialValue: CGFloat(0), trigger: model.failures) { content, x in content.offset(x: x) } keyframes: { _ in
            let reach: CGFloat = motion > 0 ? 5 : 0
            CubicKeyframe(-reach, duration: 0.05)
            CubicKeyframe(reach, duration: 0.08)
            CubicKeyframe(-reach * 0.6, duration: 0.08)
            SpringKeyframe(0, duration: 0.3 * max(motion, 0.01), spring: .bouncy)
        }
        .animation(Anim.spring(0.3 * motion, bounce: 0.2), value: model.sending)
        .animation(Anim.spring(0.3 * motion), value: model.notSent)
    }

    private func keyText(_ key: String, filled: Bool) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(filled ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
    }

    /// Where Send goes: the agent's logo and the session's title, apart from Send itself. A press
    /// opens the menu for changing it before the button sees the press (`AnnotatorToolbar.pressTarget`),
    /// so the button's own action is the accessibility press.
    /// With no target, the box asks for one, and its menu lists the sessions Vignette can start.
    /// `joined`: it sits inside the message field's box, which is its fill.
    func targetMenu(_ target: AgentDestination?, joined: Bool) -> some View {
        // The name's width is set rather than left to the text, so it springs with the bar when the
        // target changes and the controls beside it move with it. The old name leaves and the new
        // one comes in the place between, as a control does (`slot`). A long name is cut in the
        // middle, where a worktree's suffix survives; the tooltip has it whole.
        let row = target.map { model.targetRow(for: $0) }
        let title = row?.title ?? Self.chooseSession
        let nameWidth = targetNameWidth(target)
        return Button(action: onTargetMenu) {
            HStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        AgentLogo(client: target?.client ?? .claude, template: false).frame(width: 14, height: 14)
                        Text(title).font(.system(size: 13, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(width: nameWidth, alignment: .leading)
                    }
                    .id(target?.id ?? "")
                    .transition(Self.nameSwap)
                }
                .frame(width: 14 + 6 + nameWidth, alignment: .leading)
                .clipped()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: Self.chevronWidth)
            }
            .foregroundStyle(.primary)
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .frame(width: Self.targetWidth(nameWidth: nameWidth), height: 30)
            .background { TargetFill(joined: joined, hovered: targetHovered, focused: model.focus == .target) }
            .padding(Self.slop)
            .contentShape(Rectangle())
            .onHover { targetHovered = $0 }
        }
        .buttonStyle(TargetButtonStyle(joined: joined))
        .padding(Self.slop.negated)
        .fixedSize()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onTargetFrame($0) }
        .modifier(TipSpot(control: .target, text: row?.tooltip ?? Self.chooseSessionTip, hover: tip))
    }

    func targetNameWidth(_ target: AgentDestination?) -> CGFloat {
        min(ButtonLabel.width(target.map { model.targetRow(for: $0).title } ?? Self.chooseSession, size: 13), Self.targetNameMax)
    }

    private static let chevronWidth: CGFloat = 10

    /// The target's width for a name that wide. The message field's box reaches under it and the
    /// space after it, on the same spring, so the box's leading edge is the target's.
    static func targetWidth(nameWidth: CGFloat) -> CGFloat { 8 + 14 + 6 + nameWidth + 6 + chevronWidth + 9 }

    static let chooseSession = "Choose a session"
    static let chooseSessionTip = "No session is running. You can continue a past one or start a new one."
}
